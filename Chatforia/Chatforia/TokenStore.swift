import Foundation
import Security
import CryptoKit

final class TokenStore {
    static let shared = TokenStore()

    private init() {}

    private let service = Bundle.main.bundleIdentifier ?? "com.chatforia.ios"
    private let account = "chatforia.auth.token"

    func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            debugLog("🔐 TokenStore save failed: \(status)")
        }
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                debugLog("🔐 TokenStore read failed: \(status)")
            }
            return nil
        }

        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            debugLog("🔐 TokenStore clear failed: \(status)")
        }
    }
}

// A previously authenticated identity may be shown while the network is
// unavailable. The snapshot is tied to the exact Keychain token and never
// supplies credentials or proves that a revoked token is still valid online.
final class OfflineSessionStore: OfflineSessionStoring {
    static let shared = OfflineSessionStore()

    private let service = Bundle.main.bundleIdentifier ?? "com.chatforia.ios"
    private let account = "chatforia.auth.offlineSession"

    private struct Snapshot: Codable {
        let tokenDigest: String
        let user: UserDTO
    }

    func save(user: UserDTO, for token: String) {
        let snapshot = Snapshot(tokenDigest: digest(token), user: user)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let query = itemQuery
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            debugLog("Offline session snapshot save failed:", status)
        }
    }

    func user(for token: String) -> UserDTO? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.tokenDigest == digest(token) else { return nil }
        return snapshot.user
    }

    func clear() {
        SecItemDelete(itemQuery as CFDictionary)
    }

    private var itemQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
