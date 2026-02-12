//
//  SocketManager.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation
import Combine
import SocketIO

final class SocketManager: ObservableObject {
    static let shared = SocketManager()

    private let manager: SocketIO.SocketManager
    private let socket: SocketIOClient

    private init() {
        // In your project, Environment.apiBaseURL is a URL (per Xcode error)
        // This should be the base host, e.g. http://localhost:5002 or https://api.chatforia.com
        let url: URL = Environment.apiBaseURL

        self.manager = SocketIO.SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .path("/socket.io"),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(1),
                .forceWebsockets(true)
            ]
        )

        self.socket = manager.defaultSocket
    }

    func connect(token: String) {
        // Your backend reads handshake.auth.token
        socket.connect(withPayload: ["token": token])
    }

    func disconnect() {
        socket.disconnect()
    }

    func emit(_ event: String, _ payload: [String: Any]) {
        socket.emit(event, payload)
    }

    func on(_ event: String, callback: @escaping NormalCallback) {
        socket.on(event, callback: callback)
    }

    func off(_ event: String) {
        socket.off(event)
    }
}
