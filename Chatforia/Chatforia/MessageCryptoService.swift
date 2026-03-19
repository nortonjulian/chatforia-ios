import Foundation
import CryptoKit

enum MessageCryptoError: LocalizedError {
    case invalidRecipientPublicKey
    case invalidUTF8
    case missingSenderPublicKey
    case noRecipients

    var errorDescription: String? {
        switch self {
        case .invalidRecipientPublicKey:
            return "Invalid recipient public key."
        case .invalidUTF8:
            return "Invalid UTF-8 plaintext."
        case .missingSenderPublicKey:
            return "Missing sender public key."
        case .noRecipients:
            return "No recipients available for encryption."
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
        recipientPublicKeyBase64: String
    ) throws -> EncryptedMessagePayload {
        let recipients = [
            RecipientKeyContext(
                userId: recipientUserId,
                publicKeyBase64: recipientPublicKeyBase64
            )
        ]

        return try encryptMessageForRecipients(
            plaintext: plaintext,
            senderUserId: senderUserId,
            recipients: recipients
        )
    }

    func encryptMessageForRecipients(
        plaintext: String,
        senderUserId: Int,
        recipients: [RecipientKeyContext]
    ) throws -> EncryptedMessagePayload {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw MessageCryptoError.invalidUTF8
        }

        guard !recipients.isEmpty else {
            throw MessageCryptoError.noRecipients
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

        guard let senderPublicKeyBase64 = AccountKeyManager.shared.publicKeyBase64(),
              !senderPublicKeyBase64.isEmpty else {
            throw MessageCryptoError.missingSenderPublicKey
        }

        var encryptedKeysByUserId: [String: String] = [:]

        let senderWrapped = try wrapForUser(
            publicKeyBase64: senderPublicKeyBase64,
            userId: senderUserId
        )
        encryptedKeysByUserId[String(senderUserId)] = senderWrapped

        for recipient in recipients {
            let recipientWrapped = try wrapForUser(
                publicKeyBase64: recipient.publicKeyBase64,
                userId: recipient.userId
            )
            encryptedKeysByUserId[String(recipient.userId)] = recipientWrapped
        }

        return EncryptedMessagePayload(
            ciphertextBase64: ciphertextBase64,
            encryptedKeysByUserId: encryptedKeysByUserId
        )
    }

    func decryptMessageForCurrentBackend(
        ciphertextBase64: String,
        encryptedKeyPayloadJSON: String,
        userId: Int
    ) throws -> String {
        guard let myPrivateKeyB64 = AccountKeyManager.shared.privateKeyBase64(),
              let myPrivateKeyData = Data(base64Encoded: myPrivateKeyB64) else {
            throw NSError(
                domain: "MessageCryptoService",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Missing account private key"]
            )
        }

        let myPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: myPrivateKeyData)

        guard let payloadData = encryptedKeyPayloadJSON.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: String],
              let epkBase64 = payload["epk"],
              let wrappedKeyBase64 = payload["wrappedKey"] else {
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
