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

    // 🔥 NEW: Track random queue state
    private var isInRandomQueue = false

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

    // 🔥 IMPORTANT: ensures safe emit timing
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
        isInRandomQueue = false
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
            print("⚠️ socket emit skipped (not connected) event=\(event)")
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

        guard let socket = socket, socket.status == .connected else { return }
        socket.emit("join_room", roomId)
    }

    func leaveRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.remove(roomId)

        guard let socket = socket, socket.status == .connected else { return }
        socket.emit("leave_room", roomId)
    }

    // MARK: - 🔥 RANDOM MATCHING

    func joinRandomQueue(topic: String? = nil, region: String? = nil) {
        guard !isInRandomQueue else {
            print("ℹ️ already in random queue")
            return
        }

        onConnectedOnce {
            var payload: [String: Any] = [:]

            if let topic, !topic.isEmpty {
                payload["topic"] = topic
            }

            if let region, !region.isEmpty {
                payload["region"] = region
            }

            self.emit("random:join", payload)
            self.isInRandomQueue = true
        }
    }

    func leaveRandomQueue() {
        guard isInRandomQueue else { return }

        emit("random:leave")
        isInRandomQueue = false
    }

    func markRandomMatchCompleted() {
        isInRandomQueue = false
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
    }
}
