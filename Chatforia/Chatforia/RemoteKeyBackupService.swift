import Foundation
import CryptoKit
import CommonCrypto
import Security

enum RemoteKeyBackupError: Error, LocalizedError {
    case invalidPassword
    case invalidKeyMaterial
    case encodingFailed
    case decryptFailed
    case keyMismatch

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return appText("encryptionRecovery.errors.invalidPassword", languageCode: appLanguage)
        case .invalidKeyMaterial:
            return appText("encryptionRecovery.errors.invalidKeyMaterial", languageCode: appLanguage)
        case .encodingFailed:
            return appText("encryptionRecovery.errors.encodingFailed", languageCode: appLanguage)
        case .decryptFailed:
            return appText("encryptionRecovery.errors.decryptFailed", languageCode: appLanguage)
        case .keyMismatch:
            return appText("encryptionRecovery.errors.keyMismatch", languageCode: appLanguage)
        }
    }
}

struct RemoteKeyBackupPayload: Encodable {
    let publicKey: String
    let encryptedPrivateKeyBundle: String
    let privateKeyWrapSalt: String
    let privateKeyWrapKdf: String
    let privateKeyWrapIterations: Int
    let privateKeyWrapVersion: Int
}

struct RemoteKeyBackupResponse: Decodable {
    let ok: Bool?
    let hasBackup: Bool?
    let keys: RemoteKeyBackupRecord?
    let backupUpdatedAt: String?
}

struct RemoteKeyBackupRecord: Decodable {
    let publicKey: String?
    let encryptedPrivateKeyBundle: String?
    let privateKeyWrapSalt: String?
    let privateKeyWrapKdf: String?
    let privateKeyWrapIterations: Int?
    let privateKeyWrapVersion: Int?
}

struct RotateKeyPayload: Encodable {
    let publicKey: String
    let invalidateExistingBackup: Bool
}

struct RotateKeyResponse: Decodable {
    let ok: Bool?
    let publicKey: String?
    let hasBackup: Bool?
    let rotatedAt: String?
}

final class RemoteKeyBackupService {
    static let shared = RemoteKeyBackupService()
    private init() {}

    private let iterations = 250_000

    func uploadCurrentDeviceKeyBackup(
        token: String,
        userId: Int,
        password: String
    ) async throws {
        guard !password.isEmpty else {
            throw RemoteKeyBackupError.invalidPassword
        }

        guard let publicKeyBase64 =
            AccountKeyManager.shared.publicKeyBase64(userId: userId),
              let privateKeyBase64 =
            AccountKeyManager.shared.privateKeyBase64(userId: userId)
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let payload = try encryptKeyBundle(
            publicKey: publicKeyBase64,
            privateKey: privateKeyBase64,
            password: password
        )

        let body = try JSONEncoder().encode(payload)

        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "auth/keys/backup",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func fetchRemoteKeyBackupResponse(
        token: String
    ) async throws -> RemoteKeyBackupResponse {
        try await APIClient.shared.send(
            APIRequest(
                path: "auth/keys/backup",
                method: .GET,
                body: nil,
                requiresAuth: true
            ),
            token: token
        )
    }

    func fetchRemoteKeyBackup(
        token: String
    ) async throws -> RemoteKeyBackupRecord? {
        let response = try await fetchRemoteKeyBackupResponse(token: token)
        return response.keys
    }

    func hasRemoteBackup(token: String) async -> Bool {
        do {
            let response = try await fetchRemoteKeyBackupResponse(token: token)

            if let hasBackup = response.hasBackup {
                return hasBackup
            }

            return response.keys?.encryptedPrivateKeyBundle != nil
        } catch {
            return false
        }
    }

    func deleteRemoteKeyBackup(token: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "auth/keys/backup",
                method: .DELETE,
                body: nil,
                requiresAuth: true
            ),
            token: token
        )
    }

    func restoreAccountKeysFromRemoteBackup(
        token: String,
        userId: Int,
        password: String
    ) async throws {
        guard !password.isEmpty else {
            throw RemoteKeyBackupError.invalidPassword
        }

        let fetchedKeys = try await fetchRemoteKeyBackup(token: token)

        guard let keys = fetchedKeys,
              let serverPublicKey = keys.publicKey,
              let encryptedBundle = keys.encryptedPrivateKeyBundle,
              let saltBase64 = keys.privateKeyWrapSalt,
              let iterations = keys.privateKeyWrapIterations
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let decrypted: [String: String]

        do {
            decrypted = try decryptKeyBundle(
                encryptedBundle: encryptedBundle,
                password: password,
                saltBase64: saltBase64,
                iterations: iterations
            )
        } catch {
            throw RemoteKeyBackupError.decryptFailed
        }

        guard let restoredPublicKey = decrypted["publicKey"],
              let restoredPrivateKey = decrypted["privateKey"]
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        guard restoredPublicKey == serverPublicKey else {
            throw RemoteKeyBackupError.keyMismatch
        }

        try AccountKeyManager.shared.saveAccountKeys(
            userId: userId,
            publicKeyBase64: restoredPublicKey,
            privateKeyBase64: restoredPrivateKey
        )
    }

    private func encryptKeyBundle(
        publicKey: String,
        privateKey: String,
        password: String
    ) throws -> RemoteKeyBackupPayload {
        let salt = randomData(count: 16)
        let iv = randomData(count: 12)

        let wrappingKeyData = try pbkdf2SHA256(
            password: password,
            salt: salt,
            iterations: iterations,
            keyByteCount: 32
        )

        let wrappingKey = SymmetricKey(data: wrappingKeyData)

        let json: [String: String] = [
            "publicKey": publicKey,
            "privateKey": privateKey
        ]

        let plaintext = try JSONSerialization.data(
            withJSONObject: json,
            options: []
        )

        let sealed = try AES.GCM.seal(
            plaintext,
            using: wrappingKey,
            nonce: try AES.GCM.Nonce(data: iv)
        )

        let ciphertextPlusTag = sealed.ciphertext + sealed.tag

        let bundleObject: [String: String] = [
            "ivB64": iv.base64EncodedString(),
            "ctB64": ciphertextPlusTag.base64EncodedString()
        ]

        let bundleData = try JSONSerialization.data(
            withJSONObject: bundleObject,
            options: []
        )

        guard let bundleString = String(data: bundleData, encoding: .utf8) else {
            throw RemoteKeyBackupError.encodingFailed
        }

        return RemoteKeyBackupPayload(
            publicKey: publicKey,
            encryptedPrivateKeyBundle: bundleString,
            privateKeyWrapSalt: salt.base64EncodedString(),
            privateKeyWrapKdf: "PBKDF2-SHA256",
            privateKeyWrapIterations: iterations,
            privateKeyWrapVersion: 1
        )
    }

    private func decryptKeyBundle(
        encryptedBundle: String,
        password: String,
        saltBase64: String,
        iterations: Int
    ) throws -> [String: String] {
        guard let bundleData = encryptedBundle.data(using: .utf8),
              let bundleObject = try JSONSerialization.jsonObject(with: bundleData) as? [String: String],
              let ivBase64 = bundleObject["ivB64"],
              let ciphertextBase64 = bundleObject["ctB64"],
              let iv = Data(base64Encoded: ivBase64),
              let ciphertextPlusTag = Data(base64Encoded: ciphertextBase64),
              let salt = Data(base64Encoded: saltBase64)
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        guard ciphertextPlusTag.count >= 16 else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let wrappingKeyData = try pbkdf2SHA256(
            password: password,
            salt: salt,
            iterations: iterations,
            keyByteCount: 32
        )

        let wrappingKey = SymmetricKey(data: wrappingKeyData)

        let ciphertext = ciphertextPlusTag.dropLast(16)
        let tag = ciphertextPlusTag.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: iv),
            ciphertext: ciphertext,
            tag: tag
        )

        let plaintext = try AES.GCM.open(sealedBox, using: wrappingKey)

        guard let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: String] else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        return json
    }

    private func randomData(count: Int) -> Data {
        var data = Data(count: count)

        let result = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                count,
                pointer.baseAddress!
            )
        }

        precondition(result == errSecSuccess)

        return data
    }

    private func pbkdf2SHA256(
        password: String,
        salt: Data,
        iterations: Int,
        keyByteCount: Int
    ) throws -> Data {
        let passwordData = Data(password.utf8)
        var derived = Data(count: keyByteCount)

        let result = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw RemoteKeyBackupError.encodingFailed
        }

        return derived
    }
}
