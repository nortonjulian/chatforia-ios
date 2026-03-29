import Foundation
import CryptoKit

enum DevicePairingCryptoError: Error, LocalizedError {
    case missingAccountKeys
    case invalidBrowserPublicKey
    case invalidUTF8
    case invalidWrappedPayload
    case invalidNonce
    case invalidCiphertext
    case invalidPayloadJSON

    var errorDescription: String? {
        switch self {
        case .missingAccountKeys:
            return "Missing local account keys."
        case .invalidBrowserPublicKey:
            return "Invalid browser public key."
        case .invalidUTF8:
            return "Failed to encode payload."
        case .invalidWrappedPayload:
            return "Wrapped payload is invalid."
        case .invalidNonce:
            return "Wrapped payload nonce is invalid."
        case .invalidCiphertext:
            return "Wrapped payload ciphertext is invalid."
        case .invalidPayloadJSON:
            return "Wrapped payload JSON is invalid."
        }
    }
}

struct WrappedAccountKeyPayload: Encodable, Decodable {
    let version: Int
    let algorithm: String
    let senderPublicKey: String
    let nonce: String
    let ciphertext: String
}

final class DevicePairingCrypto {
    static let shared = DevicePairingCrypto()
    private init() {}

    private let algorithm = "x25519-aesgcm"
    private let version = 1

    func wrapAccountKeysForBrowser(browserPublicKeyBase64: String) throws -> WrappedAccountKeyPayload {
        guard let accountPublicKey = AccountKeyManager.shared.publicKeyBase64(),
              let accountPrivateKey = AccountKeyManager.shared.privateKeyBase64()
        else {
            throw DevicePairingCryptoError.missingAccountKeys
        }

        guard let browserPublicKeyData = Data(base64Encoded: browserPublicKeyBase64) else {
            throw DevicePairingCryptoError.invalidBrowserPublicKey
        }

        let browserPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            browserPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: browserPublicKeyData)
        } catch {
            throw DevicePairingCryptoError.invalidBrowserPublicKey
        }

        guard let accountPrivateKeyData = Data(base64Encoded: accountPrivateKey) else {
            throw DevicePairingCryptoError.missingAccountKeys
        }

        let accountPrivateKeyObj = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: accountPrivateKeyData
        )

        let sharedSecret = try accountPrivateKeyObj.sharedSecretFromKeyAgreement(with: browserPublicKey)

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("chatforia-device-pairing-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let plaintextObject: [String: String] = [
            "publicKey": accountPublicKey,
            "privateKey": accountPrivateKey
        ]

        let plaintextData = try JSONSerialization.data(withJSONObject: plaintextObject, options: [])

        let nonceData = randomData(count: 12)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(plaintextData, using: symmetricKey, nonce: nonce)

        let ciphertextPlusTag = sealed.ciphertext + sealed.tag

        return WrappedAccountKeyPayload(
            version: version,
            algorithm: algorithm,
            senderPublicKey: accountPublicKey,
            nonce: nonceData.base64EncodedString(),
            ciphertext: ciphertextPlusTag.base64EncodedString()
        )
    }

    func unwrapAccountKeysFromBrowserPayload(
        wrapped: WrappedAccountKeyPayload,
        browserPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> (publicKey: String, privateKey: String) {
        guard let senderPublicKeyData = Data(base64Encoded: wrapped.senderPublicKey) else {
            throw DevicePairingCryptoError.invalidWrappedPayload
        }

        let senderPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: senderPublicKeyData
        )

        let sharedSecret = try browserPrivateKey.sharedSecretFromKeyAgreement(with: senderPublicKey)

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("chatforia-device-pairing-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        guard let nonceData = Data(base64Encoded: wrapped.nonce) else {
            throw DevicePairingCryptoError.invalidNonce
        }

        guard let ciphertextPlusTag = Data(base64Encoded: wrapped.ciphertext),
              ciphertextPlusTag.count >= 16
        else {
            throw DevicePairingCryptoError.invalidCiphertext
        }

        let ciphertext = ciphertextPlusTag.dropLast(16)
        let tag = ciphertextPlusTag.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )

        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        guard let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: String],
              let publicKey = json["publicKey"],
              let privateKey = json["privateKey"]
        else {
            throw DevicePairingCryptoError.invalidPayloadJSON
        }

        return (publicKey, privateKey)
    }

    private func randomData(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return data
    }
}
