//
//  SocketManager.swift
//  Chatforia
//
//  Works with Socket.IO-Client-Swift where:
//  - SocketManager(socketURL:config:) takes [SocketIOClientOption]
//  - socket.emit(event, items...)
//  - socket.on(...) returns UUID and socket.off(id:) removes it
//

import Foundation
import Combine
import SocketIO

// MARK: - Notification helpers
extension Notification.Name {
    /// Posted when a message expires via socket event.
    /// userInfo["payload"] => [String: Any] (raw server payload)
    static let socketMessageExpired = Notification.Name("socketMessageExpired")
}

@MainActor
final class SocketManager: ObservableObject {
    static let shared = SocketManager()

    @Published private(set) var isConnected: Bool = false

    private let url: URL = AppEnvironment.apiBaseURL   // MUST be host root (no /api)

    private var manager: SocketIO.SocketManager?
    private var socket: SocketIOClient?

    private var didBindCoreHandlers = false
    private var currentToken: String?

    // ✅ Track joined rooms so we can re-join on reconnect and avoid redundant emits
    private var joinedRoomIds = Set<Int>()

    private init() {}

    // MARK: - Connection

    /// Backwards-compatible synchronous connect. This triggers rebuild(token:) then begins handshake.
    func connect(token: String) {
        currentToken = token
        print("SocketManager.connect invoked tokenPresent=\(!token.isEmpty) tokenPreview=\(token.prefix(8))")
        rebuild(token: token)

        guard let socket = self.socket else { return }
        if socket.status != .connected && socket.status != .connecting {
            socket.connect()
        }
    }

    /// Async connect that suspends until `.connect` event or timeout.
    /// Usage: `try await SocketManager.shared.connectAsync(token: token, timeoutSecs: 8)`
    func connectAsync(token: String?, timeoutSecs: TimeInterval = 8) async throws {
        currentToken = token
        rebuild(token: token)

        guard let socket = self.socket else {
            throw NSError(domain: "SocketManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Socket not initialized"])
        }

        // If already connected, update state and return
        if socket.status == .connected {
            await MainActor.run { self.isConnected = true }
            return
        }

        // Start connection if necessary
        if socket.status != .connected && socket.status != .connecting {
            socket.connect()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            var handlerId: UUID? = nil

            // One-off connect handler
            let connectHandler: NormalCallback = { [weak self] _, _ in
                Task { @MainActor in
                    guard !didResume else { return }
                    didResume = true
                    self?.isConnected = true

                    // Unwrap captured handlerId and call off if present with the correct label
                    if let idToRemove = handlerId {
                        self?.socket?.off(id: idToRemove)
                    }

                    continuation.resume(returning: ())
                }
            }

            // Register handler and keep id so we can remove it after resume
            let id = socket.on(clientEvent: .connect, callback: connectHandler)
            handlerId = id

            // Timeout fallback task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSecs * 1_000_000_000))
                if !didResume {
                    didResume = true
                    if let idToRemove = handlerId {
                        socket.off(id: idToRemove)
                    }
                    continuation.resume(throwing: NSError(domain: "SocketManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket connect timeout"]))
                }
            }
        }
    }

    /// Call the handler *once* when the socket next becomes connected (or immediately if already connected).
    /// Useful if you prefer a closure API instead of async/await.
    func onConnectedOnce(_ handler: @escaping () -> Void) {
        // If already connected, call immediately on main actor
        if let s = socket, s.status == .connected {
            Task { @MainActor in handler() }
            return
        }

        // Otherwise register a temporary connect handler and remove it after firing
        let callback: NormalCallback = { _, _ in
            Task { @MainActor in
                handler()
            }
        }

        // Use optional registration so we get an Optional<UUID>
        if let id = socket?.on(clientEvent: .connect, callback: callback) {
            // Remove the handler once it runs; schedule a small delay to allow callback to execute
            Task {
                try? await Task.sleep(nanoseconds: 100_000) // tiny delay
                self.socket?.off(id: id)
            }
        } else {
            // If we couldn't get an id, schedule a fallback call
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                handler()
            }
        }
    }

    func disconnect() {
        socket?.disconnect()
        isConnected = false
        joinedRoomIds.removeAll()
    }

    private func rebuild(token: String?) {
        socket?.disconnect()
        socket = nil
        manager = nil
        didBindCoreHandlers = false
        // IMPORTANT: Do NOT clear joinedRoomIds here. Keep the desired rooms so we can re-join after reconnect.
        // joinedRoomIds.removeAll()

        // Base config (unchanged)
        let baseConfig: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .path("/socket.io"),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1),
            .forceWebsockets(true)
        ]

        // Build final config — *do not* rely on +/append/insert to avoid compiler overload issues.
        let config: SocketIOClientConfiguration
        if let t = token, !t.isEmpty {
            // Put connectParams first so the handshake gets the token
            config = [
                .connectParams(["token": t]),
                .log(false),
                .compress,
                .path("/socket.io"),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(1),
                .forceWebsockets(true)
            ]
            let preview = String(t.prefix(8))
            print("SocketManager.rebuild: tokenPreview=\(preview)…")
        } else {
            config = baseConfig
        }

        // Create manager using the base URL (no token in the URL)
        let mgr = SocketIO.SocketManager(socketURL: url, config: config)
        self.manager = mgr
        self.socket = mgr.defaultSocket

        // Log visible manager URL (this will not show the token — token printed separately)
        print("SocketManager.rebuild: manager socketURL=\(String(describing: mgr.socketURL))")

        bindCoreHandlersIfNeeded()
    }

    // MARK: - Public helpers

    /// Register an event handler. Returns the UUID handler id from Socket.IO if available.
    @discardableResult
    func on(_ event: String, callback: @escaping NormalCallback) -> UUID? {
        if let id = socket?.on(event, callback: callback) {
            return id
        }
        return nil
    }

    /// Remove a handler by UUID
    func off(_ id: UUID) {
        // Call the underlying Socket.IO API with the labeled parameter 'id:'
        socket?.off(id: id)
    }

    /// Remove all handlers for an event name
    func off(_ event: String) {
        socket?.off(event)
    }

    func emit(_ event: String, _ payload: [String: Any]) {
        guard let socket = socket, socket.status == .connected else {
            print("⚠️ socket emit skipped (not connected) event=\(event) payloadPreview=\(payload.keys)")
            return
        }
        socket.emit(event, payload)
    }

    func emit(_ event: String) {
        guard let socket = socket, socket.status == .connected else {
            print("⚠️ socket emit skipped (not connected) event=\(event)")
            return
        }
        socket.emit(event)
    }

    // MARK: - Rooms

    /// Join a single room (back-compat, matches server 'join_room')
    func joinRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.insert(roomId)
        guard let socket = socket, socket.status == .connected else {
            print("ℹ️ joinRoom queued (not connected) roomId=\(roomId)")
            return
        }
        socket.emit("join_room", roomId)
    }

    /// Leave a single room (matches server 'leave_room')
    func leaveRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.remove(roomId)
        guard let socket = socket, socket.status == .connected else {
            print("ℹ️ leaveRoom queued (not connected) roomId=\(roomId)")
            return
        }
        socket.emit("leave_room", roomId)
    }

    /// ✅ Preferred: join many rooms at once (matches server 'join:rooms')
    /// - Sends `[Int]` (array) which your server expects.
    /// - Updates local joinedRoomIds so we can rejoin after reconnect.
    func joinRooms(_ roomIds: [Int]) {
        let ids = Array(Set(roomIds.filter { $0 > 0 }))
        guard !ids.isEmpty else { return }

        for id in ids { joinedRoomIds.insert(id) }
        guard let socket = socket, socket.status == .connected else {
            print("ℹ️ joinRooms queued (not connected) ids=\(ids)")
            return
        }
        socket.emit("join:rooms", ids)
    }

    /// Convenience: replace currently-joined set with a new set (diff join/leave).
    /// Uses bulk join for additions and per-room leave for removals (since server has only leave_room).
    func setActiveRooms(_ roomIds: [Int]) {
        let desired = Set(roomIds.filter { $0 > 0 })

        let toLeave = joinedRoomIds.subtracting(desired)
        let toJoin = desired.subtracting(joinedRoomIds)

        for rid in toLeave {
            guard let socket = socket, socket.status == .connected else {
                print("ℹ️ leave_room queued (not connected) rid=\(rid)")
                continue
            }
            socket.emit("leave_room", rid)
        }

        if !toJoin.isEmpty {
            if let s = socket, s.status == .connected {
                s.emit("join:rooms", Array(toJoin))
            } else {
                print("⚠️ join:rooms queued (not connected) ids=\(Array(toJoin))")
            }
        }
        joinedRoomIds = desired
    }

    // MARK: - Core handlers

    private func bindCoreHandlersIfNeeded() {
        guard !didBindCoreHandlers, let socket = self.socket else { return }
        didBindCoreHandlers = true

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let strongSelf = self else { return }
                strongSelf.isConnected = true
                print("✅ socket connected")

                // ✅ Re-join rooms after reconnect/connect (important with auto-reconnect)
                let rooms = Array(strongSelf.joinedRoomIds)
                if !rooms.isEmpty {
                    strongSelf.socket?.emit("join:rooms", rooms)
                }
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { @MainActor in
                self?.isConnected = false
                print("⚠️ socket disconnected:", data)
            }
        }

        socket.on(clientEvent: .error) { data, _ in
            print("❌ socket error:", data)
        }

        socket.on(clientEvent: .reconnect) { data, _ in
            print("🔄 socket reconnect:", data)
        }

        // ---------------------------------------------------------------------
        // Application-level socket events
        // ---------------------------------------------------------------------

        // Handle message expired events from server
        // Posts the raw payload dictionary to NotificationCenter so view-models can decode/update.
        socket.on("message:expired") { data, ack in
            guard let payload = data.first as? [String: Any] else { return }

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .socketMessageExpired,
                    object: nil,
                    userInfo: ["payload": payload]
                )
            }
        }
    }
}
