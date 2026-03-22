import Foundation
import Combine
import SocketIO

extension Notification.Name {
    static let socketMessageExpired = Notification.Name("socketMessageExpired")
    static let socketMessageEdited = Notification.Name("socketMessageEdited")
    static let socketMessageDeleted = Notification.Name("socketMessageDeleted")
}

@MainActor
final class SocketManager: ObservableObject {
    static let shared = SocketManager()

    @Published private(set) var isConnected: Bool = false

    private let url: URL = AppEnvironment.apiBaseURL

    private var manager: SocketIO.SocketManager?
    private var socket: SocketIOClient?

    private var didBindCoreHandlers = false
    private var currentToken: String?

    private var joinedRoomIds = Set<Int>()

    private init() {}

    // MARK: - Connection

    func connect(token: String) {
        currentToken = token
        print("SocketManager.connect invoked tokenPresent=\(!token.isEmpty) tokenPreview=\(token.prefix(8))")
        rebuild(token: token)

        guard let socket = self.socket else { return }
        if socket.status != .connected && socket.status != .connecting {
            socket.connect()
        }
    }

    func connectAsync(token: String?, timeoutSecs: TimeInterval = 8) async throws {
        currentToken = token
        rebuild(token: token)

        guard let socket = self.socket else {
            throw NSError(
                domain: "SocketManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Socket not initialized"]
            )
        }

        if socket.status == .connected {
            await MainActor.run { self.isConnected = true }
            return
        }

        if socket.status != .connected && socket.status != .connecting {
            socket.connect()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            var handlerId: UUID? = nil

            let connectHandler: NormalCallback = { [weak self] _, _ in
                Task { @MainActor in
                    guard !didResume else { return }
                    didResume = true
                    self?.isConnected = true

                    if let idToRemove = handlerId {
                        self?.socket?.off(id: idToRemove)
                    }

                    continuation.resume(returning: ())
                }
            }

            let id = socket.on(clientEvent: .connect, callback: connectHandler)
            handlerId = id

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSecs * 1_000_000_000))
                if !didResume {
                    didResume = true
                    if let idToRemove = handlerId {
                        socket.off(id: idToRemove)
                    }
                    continuation.resume(
                        throwing: NSError(
                            domain: "SocketManager",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Socket connect timeout"]
                        )
                    )
                }
            }
        }
    }

    func onConnectedOnce(_ handler: @escaping () -> Void) {
        if let s = socket, s.status == .connected {
            Task { @MainActor in handler() }
            return
        }

        let callback: NormalCallback = { _, _ in
            Task { @MainActor in
                handler()
            }
        }

        if let id = socket?.on(clientEvent: .connect, callback: callback) {
            Task {
                try? await Task.sleep(nanoseconds: 100_000)
                self.socket?.off(id: id)
            }
        } else {
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
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

        let baseConfig: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .path("/socket.io"),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1),
            .forceWebsockets(true)
        ]

        let config: SocketIOClientConfiguration
        if let t = token, !t.isEmpty {
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

        let mgr = SocketIO.SocketManager(socketURL: url, config: config)
        self.manager = mgr
        self.socket = mgr.defaultSocket

        print("SocketManager.rebuild: manager socketURL=\(String(describing: mgr.socketURL))")

        bindCoreHandlersIfNeeded()
    }

    // MARK: - Public helpers

    @discardableResult
    func on(_ event: String, callback: @escaping NormalCallback) -> UUID? {
        socket?.on(event, callback: callback)
    }

    func off(_ id: UUID) {
        socket?.off(id: id)
    }

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

    func joinRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.insert(roomId)

        guard let socket = socket, socket.status == .connected else {
            print("ℹ️ joinRoom queued (not connected) roomId=\(roomId)")
            return
        }

        socket.emit("join_room", roomId)
    }

    func leaveRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.remove(roomId)

        guard let socket = socket, socket.status == .connected else {
            print("ℹ️ leaveRoom queued (not connected) roomId=\(roomId)")
            return
        }

        socket.emit("leave_room", roomId)
    }

    func joinRooms(_ roomIds: [Int]) {
        let ids = Array(Set(roomIds.filter { $0 > 0 }))
        guard !ids.isEmpty else { return }

        for id in ids {
            joinedRoomIds.insert(id)
        }

        guard let socket = socket, socket.status == .connected else {
            print("ℹ️ joinRooms queued (not connected) ids=\(ids)")
            return
        }

        socket.emit("join:rooms", ids)
    }

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
            if let socket = socket, socket.status == .connected {
                socket.emit("join:rooms", Array(toJoin))
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
                guard let self else { return }
                self.isConnected = true
                print("✅ socket connected")

                if let token = self.currentToken {
                    Task.detached {
                        await DeviceRegistrationService.shared.heartbeat(token: token)
                    }
                }

                let rooms = Array(self.joinedRoomIds)
                if !rooms.isEmpty {
                    self.socket?.emit("join:rooms", rooms)
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

        // MARK: - Application-level socket events

        socket.on("message:ack") { data, _ in
            guard let payload = data.first as? [String: Any],
                  let clientMessageId = payload["clientMessageId"] as? String else {
                return
            }

            Task { @MainActor in
                MessageStore.shared.markDeliveryState(
                    clientMessageId: clientMessageId,
                    state: .delivered
                )
            }
        }

        socket.on("message_read") { data, _ in
            guard let payload = data.first as? [String: Any],
                  let messageId = payload["messageId"] as? Int else {
                return
            }

            Task { @MainActor in
                MessageStore.shared.markMessageRead(messageId: messageId)
            }
        }

        socket.on("message:expired") { data, _ in
            guard let payload = data.first as? [String: Any] else { return }

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .socketMessageExpired,
                    object: nil,
                    userInfo: ["payload": payload]
                )
            }
        }

        socket.on("message_edited") { data, _ in
            guard let payload = data.first as? [String: Any] else { return }

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .socketMessageEdited,
                    object: nil,
                    userInfo: ["payload": payload]
                )
            }
        }

        socket.on("message_deleted") { data, _ in
            guard let payload = data.first as? [String: Any] else { return }

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .socketMessageDeleted,
                    object: nil,
                    userInfo: ["payload": payload]
                )
            }
        }
    }
}
