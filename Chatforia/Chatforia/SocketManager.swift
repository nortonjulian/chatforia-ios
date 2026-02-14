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

@MainActor
final class SocketManager: ObservableObject {
    static let shared = SocketManager()

    @Published private(set) var isConnected: Bool = false

    private let url: URL = Environment.apiBaseURL   // MUST be host root (no /api)

    private var manager: SocketIO.SocketManager?
    private var socket: SocketIOClient?

    private var didBindCoreHandlers = false
    private var currentToken: String?

    // ✅ Track joined rooms so we can re-join on reconnect and avoid redundant emits
    private var joinedRoomIds = Set<Int>()

    private init() {}

    // MARK: - Connection

    func connect(token: String) {
        currentToken = token

        // Rebuild manager/socket so token is always in connectParams (including reconnects)
        rebuild(token: token)

        guard let socket else { return }
        if socket.status != .connected && socket.status != .connecting {
            socket.connect()
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
        joinedRoomIds.removeAll()

        // ✅ Build URL with token query param (your server reads handshake.query.token)
        var finalURL = url
        if let token, !token.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "token", value: token)
            ]
            if let newURL = components?.url {
                finalURL = newURL
            }
        }

        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .path("/socket.io"),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1),
            .forceWebsockets(true)
        ]

        let mgr = SocketIO.SocketManager(socketURL: finalURL, config: config)
        self.manager = mgr
        self.socket = mgr.defaultSocket

        bindCoreHandlersIfNeeded()
    }

    // MARK: - Public helpers

    @discardableResult
    func on(_ event: String, callback: @escaping NormalCallback) -> UUID? {
        return socket?.on(event, callback: callback)
    }

    func off(_ id: UUID) {
        socket?.off(id: id)
    }

    func off(_ event: String) {
        socket?.off(event)
    }

    func emit(_ event: String, _ payload: [String: Any]) {
        socket?.emit(event, payload)
    }

    func emit(_ event: String) {
        socket?.emit(event)
    }

    // MARK: - Rooms

    /// Join a single room (back-compat, matches server 'join_room')
    func joinRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.insert(roomId)
        socket?.emit("join_room", roomId)
    }

    /// Leave a single room (matches server 'leave_room')
    func leaveRoom(roomId: Int) {
        guard roomId > 0 else { return }
        joinedRoomIds.remove(roomId)
        socket?.emit("leave_room", roomId)
    }

    /// ✅ Preferred: join many rooms at once (matches server 'join:rooms')
    /// - Sends `[Int]` (array) which your server expects.
    /// - Updates local joinedRoomIds so we can rejoin after reconnect.
    func joinRooms(_ roomIds: [Int]) {
        let ids = Array(Set(roomIds.filter { $0 > 0 }))
        guard !ids.isEmpty else { return }

        for id in ids { joinedRoomIds.insert(id) }
        socket?.emit("join:rooms", ids)
    }

    /// Convenience: replace currently-joined set with a new set (diff join/leave).
    /// Uses bulk join for additions and per-room leave for removals (since server has only leave_room).
    func setActiveRooms(_ roomIds: [Int]) {
        let desired = Set(roomIds.filter { $0 > 0 })

        let toLeave = joinedRoomIds.subtracting(desired)
        let toJoin = desired.subtracting(joinedRoomIds)

        for rid in toLeave {
            socket?.emit("leave_room", rid)
        }

        if !toJoin.isEmpty {
            socket?.emit("join:rooms", Array(toJoin))
        }

        joinedRoomIds = desired
    }

    // MARK: - Core handlers

    private func bindCoreHandlersIfNeeded() {
        guard !didBindCoreHandlers, let socket else { return }
        didBindCoreHandlers = true

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = true
                print("✅ socket connected")

                // ✅ Re-join rooms after reconnect/connect (important with auto-reconnect)
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
    }
}
