import Foundation
import CryptoKit
import CommonCrypto

enum RemoteKeyBackupError: Error, LocalizedError {
    case invalidPassword
    case invalidKeyMaterial
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid password."
        case .invalidKeyMaterial:
            return "Missing or invalid key material."
        case .encodingFailed:
            return "Failed to encode backup payload."
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

    func uploadCurrentDeviceKeyBackup(token: String, password: String) async throws {
        guard !password.isEmpty else {
            throw RemoteKeyBackupError.invalidPassword
        }

        guard let publicKeyB64 = AccountKeyManager.shared.publicKeyBase64(),
              let privateKeyB64 = AccountKeyManager.shared.privateKeyBase64()
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let wrapped = try encryptKeyBundle(
            publicKey: publicKeyB64,
            privateKey: privateKeyB64,
            password: password
        )

        let body = try JSONEncoder().encode(wrapped)

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
    
    func fetchRemoteKeyBackupResponse(token: String) async throws -> RemoteKeyBackupResponse {
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

    func fetchRemoteKeyBackup(token: String) async throws -> RemoteKeyBackupRecord? {
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

        let plaintext = try JSONSerialization.data(withJSONObject: json, options: [])
        let sealed = try AES.GCM.seal(
            plaintext,
            using: wrappingKey,
            nonce: try AES.GCM.Nonce(data: iv)
        )

        let ciphertext = sealed.ciphertext
        let tag = sealed.tag
        let ctPlusTag = ciphertext + tag

        let bundleObj: [String: String] = [
            "ivB64": iv.base64EncodedString(),
            "ctB64": ctPlusTag.base64EncodedString()
        ]

        let bundleData = try JSONSerialization.data(withJSONObject: bundleObj, options: [])
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

    private func randomData(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
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

    func restoreAccountKeysFromRemoteBackup(token: String, password: String) async throws {
        guard !password.isEmpty else {
            throw RemoteKeyBackupError.invalidPassword
        }

        guard let keys = try await fetchRemoteKeyBackup(token: token),
              let publicKey = keys.publicKey,
              let bundle = keys.encryptedPrivateKeyBundle,
              let saltB64 = keys.privateKeyWrapSalt,
              let iterations = keys.privateKeyWrapIterations
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let decrypted = try decryptKeyBundle(
            encryptedBundle: bundle,
            password: password,
            saltB64: saltB64,
            iterations: iterations
        )

        guard let restoredPublicKey = decrypted["publicKey"],
              let restoredPrivateKey = decrypted["privateKey"]
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        // Optional sanity check: restored public key should match server public key
        guard restoredPublicKey == publicKey else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        try AccountKeyManager.shared.saveAccountKeys(
            publicKeyBase64: restoredPublicKey,
            privateKeyBase64: restoredPrivateKey
        )
    }

    private func decryptKeyBundle(
        encryptedBundle: String,
        password: String,
        saltB64: String,
        iterations: Int
    ) throws -> [String: String] {
        guard let bundleData = encryptedBundle.data(using: .utf8),
              let bundleObj = try JSONSerialization.jsonObject(with: bundleData) as? [String: String],
              let ivB64 = bundleObj["ivB64"],
              let ctB64 = bundleObj["ctB64"],
              let iv = Data(base64Encoded: ivB64),
              let ctPlusTag = Data(base64Encoded: ctB64),
              let salt = Data(base64Encoded: saltB64)
        else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let wrappingKeyData = try pbkdf2SHA256(
            password: password,
            salt: salt,
            iterations: iterations,
            keyByteCount: 32
        )

        let wrappingKey = SymmetricKey(data: wrappingKeyData)

        // Web format = ciphertext + tag, with IV stored separately
        guard ctPlusTag.count >= 16 else {
            throw RemoteKeyBackupError.invalidKeyMaterial
        }

        let ciphertext = ctPlusTag.dropLast(16)
        let tag = ctPlusTag.suffix(16)

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
}
