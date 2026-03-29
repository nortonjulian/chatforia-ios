import Foundation
import CryptoKit

extension AccountKeyManager {
    func generateNewAccountKeys() throws -> (publicKeyBase64: String, privateKeyBase64: String) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        return (
            publicKeyBase64: publicKey.rawRepresentation.base64EncodedString(),
            privateKeyBase64: privateKey.rawRepresentation.base64EncodedString()
        )
    }

    func ensureLocalKeysExist(token: String) async throws -> Bool {
        if hasAccountKeys() {
            return false
        }

        let hasBackup = await RemoteKeyBackupService.shared.hasRemoteBackup(token: token)

        if hasBackup {
            return true
        }

        let newKeys = try generateNewAccountKeys()
        try saveAccountKeys(
            publicKeyBase64: newKeys.publicKeyBase64,
            privateKeyBase64: newKeys.privateKeyBase64
        )

        return false
    }

    func resetAccountEncryption(token: String) async throws {
        let newKeys = try generateNewAccountKeys()

        try saveAccountKeys(
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

struct ResetEncryptionRequest: Encodable {
    let publicKey: String
    let invalidateExistingBackup: Bool
}

struct ResetEncryptionResponse: Decodable {
    let ok: Bool
}

final class AccountKeyManager {
    static let shared = AccountKeyManager()
    private init() {}

    private let service = "com.chatforia.accountkeys"
    private let publicKeyAccount = "account.curve25519.public"
    private let privateKeyAccount = "account.curve25519.private"

    func saveAccountKeys(publicKeyBase64: String, privateKeyBase64: String) throws {
        guard let pubData = Data(base64Encoded: publicKeyBase64),
              let privData = Data(base64Encoded: privateKeyBase64) else {
            throw NSError(
                domain: "AccountKeyManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid account key data"]
            )
        }

        let okPub = KeychainHelper.save(
            data: pubData,
            service: service,
            account: publicKeyAccount
        )

        let okPriv = KeychainHelper.save(
            data: privData,
            service: service,
            account: privateKeyAccount
        )

        if !okPub || !okPriv {
            throw NSError(
                domain: "AccountKeyManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save account keys"]
            )
        }
    }

    func publicKeyBase64() -> String? {
        guard let data = KeychainHelper.read(service: service, account: publicKeyAccount) else {
            return nil
        }
        return data.base64EncodedString()
    }

    func privateKeyBase64() -> String? {
        guard let data = KeychainHelper.read(service: service, account: privateKeyAccount) else {
            return nil
        }
        return data.base64EncodedString()
    }

    func clear() {
        _ = KeychainHelper.delete(service: service, account: publicKeyAccount)
        _ = KeychainHelper.delete(service: service, account: privateKeyAccount)
    }

    func hasAccountKeys() -> Bool {
        publicKeyBase64() != nil && privateKeyBase64() != nil
    }
}
