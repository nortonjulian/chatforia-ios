//
//  SocketManager.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation
import Combine

@MainActor
final class SocketManager: ObservableObject {
    @Published private(set) var isConnected: Bool = false

    func connect(token: String) {
        // TODO: replace with real Socket.IO / WebSocket connect logic
        // For now, we just simulate "connected".
        isConnected = true
        print("🟢 Socket connected (stub) with token prefix:", token.prefix(12))
    }

    func disconnect() {
        isConnected = false
        print("🔴 Socket disconnected (stub)")
    }
}

