import Foundation
import CryptoKit
import Security

struct DeviceWrappedAccountKeyPayload: Codable {
    let alg: String
    let epk: String
    let nonce: String
    let ciphertext: String
}

struct DeviceProvisionedAccountKeyPayload: Codable {
    let privateKey: String
}

enum DeviceProvisioningError: Error, LocalizedError {
    case invalidKey
    case unsupportedAlgorithm
    case encryptionFailed
    case decryptionFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Invalid device provisioning key."
        case .unsupportedAlgorithm:
            return "Unsupported device provisioning algorithm."
        case .encryptionFailed:
            return "Failed to encrypt account key for device."
        case .decryptionFailed:
            return "Failed to decrypt account key for this device."
        case .encodingFailed:
            return "Failed to encode device provisioning payload."
        }
    }
}

final class DeviceProvisioningCrypto {
    static let shared = DeviceProvisioningCrypto()
    private init() {}

    private let algorithm = "x25519-aesgcm"

    func wrapAccountKeyForDevice(
        accountPrivateKeyBase64: String,
        targetDevicePublicKeyBase64: String
    ) throws -> String {
        guard let targetPublicKeyData = Data(base64Encoded: targetDevicePublicKeyBase64) else {
            throw DeviceProvisioningError.invalidKey
        }

        let targetPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: targetPublicKeyData
        )

        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(
            with: targetPublicKey
        )

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("chatforia-device-provision-v1".utf8),
            sharedInfo: Data("account-key".utf8),
            outputByteCount: 32
        )

        let payload = DeviceProvisionedAccountKeyPayload(
            privateKey: accountPrivateKeyBase64
        )

        let plaintext = try JSONEncoder().encode(payload)

        // AES-GCM standard nonce size is 12 bytes.
        let nonceData = randomData(count: 12)
        let nonce = try AES.GCM.Nonce(data: nonceData)

        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: symmetricKey,
            nonce: nonce
        )

        let ciphertextPlusTag = sealedBox.ciphertext + sealedBox.tag

        let wrapped = DeviceWrappedAccountKeyPayload(
            alg: algorithm,
            epk: ephemeralPrivateKey.publicKey.rawRepresentation.base64EncodedString(),
            nonce: nonceData.base64EncodedString(),
            ciphertext: ciphertextPlusTag.base64EncodedString()
        )

        let encoded = try JSONEncoder().encode(wrapped)

        guard let json = String(data: encoded, encoding: .utf8) else {
            throw DeviceProvisioningError.encodingFailed
        }

        return json
    }

    func unwrapProvisionedAccountKey(
        wrappedAccountKeyJson: String,
        currentDevicePrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> String {
        guard let data = wrappedAccountKeyJson.data(using: .utf8) else {
            throw DeviceProvisioningError.encodingFailed
        }

        let wrapped = try JSONDecoder().decode(
            DeviceWrappedAccountKeyPayload.self,
            from: data
        )

        guard wrapped.alg == algorithm else {
            throw DeviceProvisioningError.unsupportedAlgorithm
        }

        guard let epkData = Data(base64Encoded: wrapped.epk),
              let nonceData = Data(base64Encoded: wrapped.nonce),
              let ciphertextPlusTag = Data(base64Encoded: wrapped.ciphertext),
              ciphertextPlusTag.count >= 16 else {
            throw DeviceProvisioningError.invalidKey
        }

        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: epkData
        )

        let sharedSecret = try currentDevicePrivateKey.sharedSecretFromKeyAgreement(
            with: ephemeralPublicKey
        )

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("chatforia-device-provision-v1".utf8),
            sharedInfo: Data("account-key".utf8),
            outputByteCount: 32
        )

        let ciphertext = ciphertextPlusTag.dropLast(16)
        let tag = ciphertextPlusTag.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )

        let plaintext = try AES.GCM.open(
            sealedBox,
            using: symmetricKey
        )

        let payload = try JSONDecoder().decode(
            DeviceProvisionedAccountKeyPayload.self,
            from: plaintext
        )

        guard !payload.privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeviceProvisioningError.decryptionFailed
        }

        return payload.privateKey
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
}