import Foundation
import CryptoKit

enum MessageCryptoError: LocalizedError {
    case invalidRecipientPublicKey
    case invalidUTF8
    case noRecipientDevices
    case missingSenderPublicKey

    var errorDescription: String? {
        switch self {
        case .invalidRecipientPublicKey:
            return "Invalid recipient public key."
        case .invalidUTF8:
            return "Invalid UTF-8 plaintext."
        case .noRecipientDevices:
            return "No recipient devices found."
        case .missingSenderPublicKey:
            return "Missing sender public key."
        }
    }
}

final class MessageCryptoService {
    static let shared = MessageCryptoService()
    private init() {}

    func encryptMessageForCurrentBackend(
        plaintext: String,
        senderUserId: Int,
        recipientUserId: Int,
        senderPublicKeyBase64: String,
        recipientDevices: [DeviceDTO]
    ) throws -> EncryptedMessagePayload {
        guard !recipientDevices.isEmpty else {
            throw MessageCryptoError.noRecipientDevices
        }

        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw MessageCryptoError.invalidUTF8
        }

        let messageKey = SymmetricKey(size: .bits256)

        let sealedContent = try AES.GCM.seal(plaintextData, using: messageKey)
        guard let combined = sealedContent.combined else {
            throw NSError(
                domain: "MessageCryptoService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to combine sealed content"]
            )
        }

        let ciphertextBase64 = combined.base64EncodedString()

        func wrapForUser(publicKeyBase64: String, userId: Int) throws -> String {
            guard let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
                throw MessageCryptoError.invalidRecipientPublicKey
            }

            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyData)
            let ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
            let sharedSecret = try ephemeralPrivate.sharedSecretFromKeyAgreement(with: publicKey)

            let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data("chatforia-msg-wrap-v1".utf8),
                sharedInfo: Data("user:\(userId)".utf8),
                outputByteCount: 32
            )

            let messageKeyData = messageKey.withUnsafeBytes { Data($0) }
            let sealedMessageKey = try AES.GCM.seal(messageKeyData, using: wrappingKey)

            guard let wrappedCombined = sealedMessageKey.combined else {
                throw NSError(
                    domain: "MessageCryptoService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to combine wrapped message key"]
                )
            }

            let wrappedPayload: [String: String] = [
                "alg": "x25519-aesgcm",
                "epk": ephemeralPrivate.publicKey.rawRepresentation.base64EncodedString(),
                "wrappedKey": wrappedCombined.base64EncodedString()
            ]

            let wrappedPayloadData = try JSONSerialization.data(withJSONObject: wrappedPayload, options: [])
            return String(data: wrappedPayloadData, encoding: .utf8) ?? "{}"
        }

        guard let recipientDevice = recipientDevices.first,
              let recipientPublicKeyBase64 = recipientDevice.publicKey
        else {
            throw MessageCryptoError.noRecipientDevices
        }

        let recipientWrapped = try wrapForUser(
            publicKeyBase64: recipientPublicKeyBase64,
            userId: recipientUserId
        )

        guard !senderPublicKeyBase64.isEmpty else {
            throw MessageCryptoError.missingSenderPublicKey
        }

        let senderWrapped = try wrapForUser(
            publicKeyBase64: senderPublicKeyBase64,
            userId: senderUserId
        )

        return EncryptedMessagePayload(
            ciphertextBase64: ciphertextBase64,
            encryptedKeysByUserId: [
                String(senderUserId): senderWrapped,
                String(recipientUserId): recipientWrapped
            ]
        )
    }

    func decryptMessageForCurrentBackend(
        ciphertextBase64: String,
        encryptedKeyPayloadJSON: String,
        userId: Int
    ) throws -> String {
        let myPrivateKey = try DeviceKeyManager.shared.privateKey()

        guard let payloadData = encryptedKeyPayloadJSON.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: String],
              let epkBase64 = payload["epk"],
              let wrappedKeyBase64 = payload["wrappedKey"]
        else {
            throw NSError(
                domain: "MessageCryptoService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid encrypted key payload"]
            )
        }

        guard let epkData = Data(base64Encoded: epkBase64) else {
            throw NSError(
                domain: "MessageCryptoService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid ephemeral public key"]
            )
        }

        let senderEphemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: epkData)
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: senderEphemeralPublicKey)

        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("chatforia-msg-wrap-v1".utf8),
            sharedInfo: Data("user:\(userId)".utf8),
            outputByteCount: 32
        )

        guard let wrappedKeyData = Data(base64Encoded: wrappedKeyBase64) else {
            throw NSError(
                domain: "MessageCryptoService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Invalid wrapped key"]
            )
        }

        let sealedWrappedKey = try AES.GCM.SealedBox(combined: wrappedKeyData)
        let messageKeyData = try AES.GCM.open(sealedWrappedKey, using: wrappingKey)
        let messageKey = SymmetricKey(data: messageKeyData)

        guard let ciphertextData = Data(base64Encoded: ciphertextBase64) else {
            throw NSError(
                domain: "MessageCryptoService",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Invalid ciphertext"]
            )
        }

        let sealedContent = try AES.GCM.SealedBox(combined: ciphertextData)
        let plaintextData = try AES.GCM.open(sealedContent, using: messageKey)

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw MessageCryptoError.invalidUTF8
        }

        return plaintext
    }
}
