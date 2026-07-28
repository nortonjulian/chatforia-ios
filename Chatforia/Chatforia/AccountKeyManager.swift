import Foundation
import CryptoKit

struct ResetEncryptionRequest: Encodable {
    let publicKey: String
    let invalidateExistingBackup: Bool
}

struct ResetEncryptionResponse: Decodable {
    let ok: Bool?
    let publicKey: String?
    let hasBackup: Bool?
    let rotatedAt: String?
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

    private func pendingPublicKeyAccount(userId: Int) -> String {
        "account.\(userId).curve25519.pending.public"
    }

    private func pendingPrivateKeyAccount(userId: Int) -> String {
        "account.\(userId).curve25519.pending.private"
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

        _ = KeychainHelper.delete(
            service: service,
            account: publicKeyAccount(userId: userId)
        )

        _ = KeychainHelper.delete(
            service: service,
            account: privateKeyAccount(userId: userId)
        )

        clearPendingResetKeys(userId: userId)
    }

    private func savePendingResetKeys(
        userId: Int,
        publicKeyBase64: String,
        privateKeyBase64: String
    ) throws {
        guard let publicData =
                Data(base64Encoded: publicKeyBase64),
              let privateData =
                Data(base64Encoded: privateKeyBase64)
        else {
            throw NSError(
                domain: "AccountKeyManager",
                code: 54,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid pending secure message key data."
                ]
            )
        }

        let savedPublic =
            KeychainHelper.save(
                data: publicData,
                service: service,
                account: pendingPublicKeyAccount(userId: userId)
            )

        let savedPrivate =
            KeychainHelper.save(
                data: privateData,
                service: service,
                account: pendingPrivateKeyAccount(userId: userId)
            )

        guard savedPublic && savedPrivate else {
            clearPendingResetKeys(userId: userId)

            throw NSError(
                domain: "AccountKeyManager",
                code: 55,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not safely prepare the new secure message key."
                ]
            )
        }
    }

    private func clearPendingResetKeys(userId: Int) {
        guard userId > 0 else { return }

        _ = KeychainHelper.delete(
            service: service,
            account: pendingPublicKeyAccount(userId: userId)
        )

        _ = KeychainHelper.delete(
            service: service,
            account: pendingPrivateKeyAccount(userId: userId)
        )
    }

    private func reconcilePendingResetIfNeeded(
        userId: Int,
        serverPublicKey: String?
    ) throws {
        let pendingPublicData =
            KeychainHelper.read(
                service: service,
                account: pendingPublicKeyAccount(userId: userId)
            )

        let pendingPrivateData =
            KeychainHelper.read(
                service: service,
                account: pendingPrivateKeyAccount(userId: userId)
            )

        let hasPendingPublic = pendingPublicData != nil
        let hasPendingPrivate = pendingPrivateData != nil

        guard hasPendingPublic || hasPendingPrivate else {
            return
        }

        /*
         * An incomplete pending pair was never made authoritative and can
         * be discarded safely. It must never replace the active key.
         */
        guard
            let pendingPublicData,
            let pendingPrivateData
        else {
            clearPendingResetKeys(userId: userId)
            return
        }

        let pendingPublicKey =
            pendingPublicData.base64EncodedString()
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let pendingPrivateKey =
            pendingPrivateData.base64EncodedString()

        let normalizedServerKey =
            serverPublicKey?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        if !normalizedServerKey.isEmpty,
           normalizedServerKey == pendingPublicKey {
            try saveAccountKeys(
                userId: userId,
                publicKeyBase64: pendingPublicKey,
                privateKeyBase64: pendingPrivateKey
            )
        }

        /*
         * Matching means the server accepted it and it has now been
         * promoted. Nonmatching means the prior reset was rejected.
         */
        clearPendingResetKeys(userId: userId)
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

        guard me.user.id == userId else {
            throw NSError(
                domain: "AccountKeyManager",
                code: 49,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Secure message key setup failed because the signed-in user changed."
                ]
            )
        }

        let serverPublicKey = me.user.publicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        /*
         * Complete a reset that the server accepted before the app closed,
         * or discard a pending candidate that the server rejected.
         */
        try reconcilePendingResetIfNeeded(
            userId: userId,
            serverPublicKey: serverPublicKey
        )

        let localPublicKey =
            publicKeyBase64(userId: userId)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let localPrivateKey =
            privateKeyBase64(userId: userId)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let hasLocalPublicKey =
            !(localPublicKey?.isEmpty ?? true)

        let hasLocalPrivateKey =
            !(localPrivateKey?.isEmpty ?? true)

        if hasLocalPublicKey != hasLocalPrivateKey {
            throw NSError(
                domain: "AccountKeyManager",
                code: 53,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This device has incomplete secure message key information. Restore your secure messages or start fresh only as a last resort."
                ]
            )
        }

        let hasLocalKeys =
            hasLocalPublicKey && hasLocalPrivateKey

        // 1. Server has key, but device has none.
        if let serverPublicKey,
        !serverPublicKey.isEmpty,
        !hasLocalKeys {
            throw NSError(
                domain: "AccountKeyManager",
                code: 51,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This device is missing your secure message key. Restore your secure message backup or start fresh with secure messages."
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
                        "The secure message key on this device does not match your account. Restore your secure message backup or start fresh with secure messages."
                ]
            )
        }

        // 3. Device has keys, but server is missing the public key.
        // Upload the existing local public key before marking encryption ready.
        if hasLocalKeys,
        let localPublicKey,
        !localPublicKey.isEmpty,
        serverPublicKey?.isEmpty != false {

            let requestBody = ResetEncryptionRequest(
                publicKey: localPublicKey,
                invalidateExistingBackup: false
            )

            let bodyData = try JSONEncoder().encode(requestBody)

            let response: ResetEncryptionResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "auth/keys/rotate",
                    method: .POST,
                    body: bodyData,
                    requiresAuth: true
                ),
                token: token
            )

            let uploadedPublicKey = response.publicKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard uploadedPublicKey == localPublicKey else {
                throw NSError(
                    domain: "AccountKeyManager",
                    code: 52,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Secure message key setup failed. Please try again."
                    ]
                )
            }

            return false
        }

        // 4. Device has matching keys.
        if hasLocalKeys {
            return false
        }

        // 5. Brand-new account/server has no key yet.
        let newKeys = try generateNewAccountKeys()

        try saveAccountKeys(
            userId: userId,
            publicKeyBase64: newKeys.publicKeyBase64,
            privateKeyBase64: newKeys.privateKeyBase64
        )

        let requestBody = ResetEncryptionRequest(
            publicKey: newKeys.publicKeyBase64,
            invalidateExistingBackup: false
        )

        let bodyData = try JSONEncoder().encode(requestBody)

        let response: ResetEncryptionResponse = try await APIClient.shared.send(
            APIRequest(
                path: "auth/keys/rotate",
                method: .POST,
                body: bodyData,
                requiresAuth: true
            ),
            token: token
        )

        let uploadedPublicKey = response.publicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard uploadedPublicKey == newKeys.publicKeyBase64 else {
            clear(userId: userId)

            throw NSError(
                domain: "AccountKeyManager",
                code: 52,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Secure message key setup failed. Please try again."
                ]
            )
        }

        return false
    }

    func resetAccountEncryption(
        userId: Int,
        token: String
    ) async throws {
        let newKeys = try generateNewAccountKeys()

        /*
         * Keep the replacement in a pending Keychain slot. The active key
         * is not touched unless the server accepts this exact public key.
         */
        try savePendingResetKeys(
            userId: userId,
            publicKeyBase64: newKeys.publicKeyBase64,
            privateKeyBase64: newKeys.privateKeyBase64
        )

        let requestBody = ResetEncryptionRequest(
            publicKey: newKeys.publicKeyBase64,
            invalidateExistingBackup: true
        )

        let bodyData = try JSONEncoder().encode(requestBody)

        let response: ResetEncryptionResponse =
            try await APIClient.shared.send(
                APIRequest(
                    path: "auth/keys/rotate",
                    method: .POST,
                    body: bodyData,
                    requiresAuth: true
                ),
                token: token
            )

        let acceptedPublicKey =
            response.publicKey?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard acceptedPublicKey == newKeys.publicKeyBase64 else {
            /*
             * Leave the active key untouched. The pending candidate will
             * be discarded during the next authenticated reconciliation
             * because it does not match the server.
             */
            throw NSError(
                domain: "AccountKeyManager",
                code: 56,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The server did not confirm the new secure message key."
                ]
            )
        }

        /*
         * The server has accepted the replacement. Promote the pending
         * pair to the active account-scoped Keychain entries.
         */
        try saveAccountKeys(
            userId: userId,
            publicKeyBase64: newKeys.publicKeyBase64,
            privateKeyBase64: newKeys.privateKeyBase64
        )

        clearPendingResetKeys(userId: userId)
    }
}
