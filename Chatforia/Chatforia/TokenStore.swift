//
//  TokenStore.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

final class TokenStore {
    private let key = "chatforia.auth.token"

    func save(_ token: String) {
        UserDefaults.standard.set(token, forKey: key)
    }

    func read() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

