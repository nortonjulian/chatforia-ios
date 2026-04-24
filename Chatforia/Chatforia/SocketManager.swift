import Foundation
import Combine
import SocketIO

extension Notification.Name {
    static let socketMessageExpired = Notification.Name("socketMessageExpired")
    static let socketMessageEdited = Notification.Name("socketMessageEdited")
    static let socketMessageDeleted = Notification.Name("socketMessageDeleted")
    static let socketMessageUpsert = Notification.Name("socketMessageUpsert")
    static let socketDidReconnect = Notification.Name("socketDidReconnect")
    static let socketVoicemailNew = Notification.Name("socketVoicemailNew")
    static let socketVoicemailUpdated = Notification.Name("socketVoicemailUpdated")
    static let socketVoicemailDeleted = Notification.Name("socketVoicemailDeleted")
    static let socketCallIncoming = Notification.Name("socketCallIncoming")
    static let socketCallEnded = Notification.Name("socketCallEnded")
    static let socketSMSMessageNew = Notification.Name("socketSMSMessageNew")
    static let socketVideoIncoming = Notification.Name("socketVideoIncoming")
    static let socketVideoEnded = Notification.Name("socketVideoEnded")
}

@MainActor
final class SocketManager: ObservableObject {
    static let shared = SocketManager()

    @Published private(set) var isConnected: Bool = false

    private let url: URL = AppEnvironment.apiBaseURL

    private var manager: SocketIO.SocketManager?
    private var socket: SocketIOClient?

    private var currentToken: String?
    private var joinedRoomIds = Set<Int>()
    private var isInRandomQueue = false

    private init() {}

    // MARK: - Public socket helpers

    @discardableResult
    func on(_ event: String, callback: @escaping NormalCallback) -> UUID? {
        guard let socket else { return nil }
        return socket.on(event, callback: callback)
    }

    func off(_ id: UUID) {
        socket?.off(id: id)
    }

    func emit(_ event: String, _ payload: [String: Any]) {
        guard let socket, socket.status == .connected else {
            print("⚠️ socket emit skipped (not connected) event=\(event)")
            return
        }
        socket.emit(event, payload)
    }

    func emit(_ event: String) {
        guard let socket, socket.status == .connected else {
            print("⚠️ socket emit skipped (not connected) event=\(event)")
            return
        }
        socket.emit(event)
    }

    // MARK: - Connection

    func connect(token: String) {
        currentToken = token
        rebuild(token: token)

        guard let socket else { return }
        if socket.status != .connected && socket.status != .connecting {
            socket.connect()
        }
    }

    func connectAsync(token: String?, timeoutSecs: TimeInterval = 8) async throws {
        currentToken = token
        rebuild(token: token)

        guard let socket else {
            throw NSError(
                domain: "SocketManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Socket not initialized"]
            )
        }

        if socket.status == .connected {
            self.isConnected = true
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

        let params: [String: Any] = {
            guard let token, !token.isEmpty else { return [:] }
            return ["token": token]
        }()

        let config: SocketIOClientConfiguration = [
            .connectParams(params),
            .log(false),
            .compress,
            .path("/socket.io"),
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(1),
            .forceWebsockets(true)
        ]

        let mgr = SocketIO.SocketManager(socketURL: url, config: config)
        self.manager = mgr
        self.socket = mgr.defaultSocket

        bindAllHandlers()
    }

    // MARK: - Unified Handlers (Core + Realtime)

    private func bindAllHandlers() {
        guard let socket else { return }

        socket.removeAllHandlers()

        // CONNECT
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = true
                print("✅ socket connected")

                for roomId in self.joinedRoomIds {
                    socket.emit("joinRoom", ["roomId": roomId])
                    print("[SocketManager] rejoined room \(roomId)")
                }

                NotificationCenter.default.post(name: .socketDidReconnect, object: nil)
            }
        }
        
        socket.on("sms:message:new") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketSMSMessageNew,
                object: nil,
                userInfo: payload
            )
        }

        // DISCONNECT
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { @MainActor in
                self?.isConnected = false
                print("⚠️ socket disconnected:", data)
            }
        }

        // ERROR
        socket.on(clientEvent: .error) { data, _ in
            print("❌ socket error:", data)

            let message = String(describing: data).lowercased()

            if message.contains("unauthorized") || message.contains("no user found") {
                NotificationCenter.default.post(
                    name: Notification.Name("auth.session.invalid"),
                    object: nil
                )
            }
        }

        // RECONNECT
        socket.on(clientEvent: .reconnect) { data, _ in
            print("🔄 socket reconnect:", data)
        }

        socket.on("voicemail:new") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketVoicemailNew,
                object: nil,
                userInfo: payload
            )
        }

        socket.on("voicemail:updated") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketVoicemailUpdated,
                object: nil,
                userInfo: payload
            )
        }

        socket.on("voicemail:deleted") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketVoicemailDeleted,
                object: nil,
                userInfo: payload
            )
        }

        socket.on("message:upsert") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else {
                print("[SocketManager] message:upsert missing payload")
                return
            }

            NotificationCenter.default.post(
                name: .socketMessageUpsert,
                object: nil,
                userInfo: ["payload": payload]
            )
        }

        socket.on("message:edited") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketMessageEdited,
                object: nil,
                userInfo: ["payload": payload]
            )
        }

        socket.on("message:deleted") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketMessageDeleted,
                object: nil,
                userInfo: ["payload": payload]
            )
        }

        socket.on("message:expired") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketMessageExpired,
                object: nil,
                userInfo: ["payload": payload]
            )
        }
        
        socket.on("call:incoming") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketCallIncoming,
                object: nil,
                userInfo: payload
            )
        }

        socket.on("call:ended") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketCallEnded,
                object: nil,
                userInfo: payload
            )
        }
        
        socket.on("video:incoming") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketVideoIncoming,
                object: nil,
                userInfo: payload
            )
        }

        socket.on("video:ended") { [weak self] data, _ in
            guard let payload = self?.normalizeFirstPayload(data) else { return }

            NotificationCenter.default.post(
                name: .socketVideoEnded,
                object: nil,
                userInfo: payload
            )
        }
    }

    // MARK: - Rooms

    func joinRoom(_ roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.insert(roomId)

        socket?.emit("joinRoom", ["roomId": roomId])
        print("[SocketManager] joinRoom \(roomId)")
    }

    func leaveRoom(_ roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.remove(roomId)

        socket?.emit("leaveRoom", ["roomId": roomId])
        print("[SocketManager] leaveRoom \(roomId)")
    }

    // MARK: - Random Matching

    func joinRandomQueue(topic: String? = nil, region: String? = nil) {
        guard !isInRandomQueue else { return }

        var payload: [String: Any] = [:]
        if let topic { payload["topic"] = topic }
        if let region { payload["region"] = region }

        socket?.emit("random:join", payload)
        isInRandomQueue = true
    }

    func leaveRandomQueue() {
        guard isInRandomQueue else { return }
        socket?.emit("random:leave")
        isInRandomQueue = false
    }

    func markRandomMatchCompleted() {
        isInRandomQueue = false
    }

    // MARK: - Helpers
    
    private func handleInvalidSession() {
        disconnect()

        // 🔥 Clear token
        TokenStore.shared.clear()

        // 🔥 Reset app auth state
        NotificationCenter.default.post(
            name: Notification.Name("auth.session.invalid"),
            object: nil
        )
    }

    private func normalizeFirstPayload(_ data: [Any]) -> [String: Any]? {
        guard let first = data.first else { return nil }

        if let dict = first as? [String: Any] {
            return dict
        }

        if let arr = first as? [[String: Any]] {
            return arr.first
        }

        return nil
    }
}
