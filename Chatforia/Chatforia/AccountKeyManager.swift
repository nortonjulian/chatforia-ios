import Foundation
import CryptoKit

struct ResetEncryptionRequest: Encodable {
    let publicKey: String
    let invalidateExistingBackup: Bool
}

struct ResetEncryptionResponse: Decodable {
    let ok: Bool
}

private struct AuthMeKeyCheckResponse: Decodable {
    let user: AuthMeKeyCheckUser
}

private struct AuthMeKeyCheckUser: Decodable {
    let id: Int
    let publicKey: String?
}

final class AccountKeyManager {
    static let shared = AccountKeyManager()
    private init() {}

    private let service = "com.chatforia.accountkeys"

    private func publicKeyAccount(userId: Int) -> String {
        "account.\(userId).curve25519.public"
    }

    private func privateKeyAccount(userId: Int) -> String {
        "account.\(userId).curve25519.private"
    }

    func generateNewAccountKeys() throws -> (publicKeyBase64: String, privateKeyBase64: String) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        return (
            publicKeyBase64: publicKey.rawRepresentation.base64EncodedString(),
            privateKeyBase64: privateKey.rawRepresentation.base64EncodedString()
        )
    }

    func saveAccountKeys(userId: Int, publicKeyBase64: String, privateKeyBase64: String) throws {
        guard userId > 0 else {
            throw NSError(domain: "AccountKeyManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing userId"])
        }

        guard let pubData = Data(base64Encoded: publicKeyBase64),
              let privData = Data(base64Encoded: privateKeyBase64) else {
            throw NSError(domain: "AccountKeyManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid account key data"])
        }

        let okPub = KeychainHelper.save(data: pubData, service: service, account: publicKeyAccount(userId: userId))
        let okPriv = KeychainHelper.save(data: privData, service: service, account: privateKeyAccount(userId: userId))

        if !okPub || !okPriv {
            throw NSError(domain: "AccountKeyManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to save account keys"])
        }
    }

    func publicKeyBase64(userId: Int) -> String? {
        guard userId > 0 else { return nil }
        guard let data = KeychainHelper.read(service: service, account: publicKeyAccount(userId: userId)) else {
            return nil
        }
        return data.base64EncodedString()
    }

    func privateKeyBase64(userId: Int) -> String? {
        guard userId > 0 else { return nil }
        guard let data = KeychainHelper.read(service: service, account: privateKeyAccount(userId: userId)) else {
            return nil
        }
        return data.base64EncodedString()
    }

    func hasAccountKeys(userId: Int) -> Bool {
        publicKeyBase64(userId: userId) != nil && privateKeyBase64(userId: userId) != nil
    }

    func clear(userId: Int) {
        guard userId > 0 else { return }
        _ = KeychainHelper.delete(service: service, account: publicKeyAccount(userId: userId))
        _ = KeychainHelper.delete(service: service, account: privateKeyAccount(userId: userId))
    }

    func clearLegacyGlobalKeys() {
        _ = KeychainHelper.delete(service: service, account: "account.curve25519.public")
        _ = KeychainHelper.delete(service: service, account: "account.curve25519.private")
    }

    func ensureLocalKeysExist(userId: Int, token: String) async throws -> Bool {
        guard userId > 0 else { return false }

        let me: AuthMeKeyCheckResponse = try await APIClient.shared.send(
            APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
            token: token
        )

        let serverPublicKey = me.user.publicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let localPublicKey = publicKeyBase64(userId: userId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)


        // 1. Server has key, but device has none.
        if let serverPublicKey,
           !serverPublicKey.isEmpty,
           !hasAccountKeys(userId: userId) {
            throw NSError(
                domain: "AccountKeyManager",
                code: 51,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This device is missing your encryption key. Restore your backup key or reset encryption."
                ]
            )
        }

        // 2. Device has key, but it does not match server.
        if let localPublicKey,
           let serverPublicKey,
           !localPublicKey.isEmpty,
           !serverPublicKey.isEmpty,
           localPublicKey != serverPublicKey {
            throw NSError(
                domain: "AccountKeyManager",
                code: 50,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Local encryption key does not match server public key. Restore your backup key or reset encryption."
                ]
            )
        }

        // 3. Device has matching keys.
        if hasAccountKeys(userId: userId) {
            return false
        }

        // 4. Brand-new account/server has no key yet.
        let newKeys = try generateNewAccountKeys()

        try saveAccountKeys(
            userId: userId,
            publicKeyBase64: newKeys.publicKeyBase64,
            privateKeyBase64: newKeys.privateKeyBase64
        )

        return false
    }

    func resetAccountEncryption(userId: Int, token: String) async throws {
        let newKeys = try generateNewAccountKeys()

        try saveAccountKeys(
            userId: userId,
            publicKeyBase64: newKeys.publicKeyBase64,
            privateKeyBase64: newKeys.privateKeyBase64
        )

        let requestBody = ResetEncryptionRequest(
            publicKey: newKeys.publicKeyBase64,
            invalidateExistingBackup: true
        )

        let bodyData = try JSONEncoder().encode(requestBody)

        _ = try await APIClient.shared.send(
            APIRequest(
                path: "auth/keys/rotate",
                method: .POST,
                body: bodyData,
                requiresAuth: true
            ),
            token: token
        ) as ResetEncryptionResponse
    }
}
