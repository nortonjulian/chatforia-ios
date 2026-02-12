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
    }

    private func rebuild(token: String?) {
        socket?.disconnect()
        socket = nil
        manager = nil
        didBindCoreHandlers = false

        // ✅ Build URL with token query param
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
        // This Socket.IO client expects "items" without labels, and dictionary is fine
        socket?.emit(event, payload)
    }

    func emit(_ event: String) {
        socket?.emit(event)
    }

    // Optional: room helpers (matches your JS semantics)
    func joinRoom(roomId: Int) {
        emit("room:join", ["roomId": roomId])
    }

    func leaveRoom(roomId: Int) {
        emit("room:leave", ["roomId": roomId])
    }

    // MARK: - Core handlers

    private func bindCoreHandlersIfNeeded() {
        guard !didBindCoreHandlers, let socket else { return }
        didBindCoreHandlers = true

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.isConnected = true
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
