// Standalone test harness. Compile with the production MessageCryptoService.swift;
// these types replace app dependencies only in this isolated executable.
import Foundation
import CryptoKit

struct RecipientKeyContext {
    let userId: Int
    let publicKeyBase64: String
}
struct EncryptedMessagePayload {
    let ciphertextBase64: String
    let encryptedKeysByUserId: [String: String]
}
struct EncryptedMessagePayloadForUser {
    let contentCiphertext: String
    let encryptedKey: String
    let language: String?
    let sourceLanguage: String?
}
final class AccountKeyManager {
    static let shared = AccountKeyManager()
    let key = Curve25519.KeyAgreement.PrivateKey()
    func publicKeyBase64(userId: Int) -> String? {
        key.publicKey.rawRepresentation.base64EncodedString()
    }
    func privateKeyBase64(userId: Int) -> String? {
        key.rawRepresentation.base64EncodedString()
    }
}
@main
struct VerifyOriginalCrypto {
    static func main() throws {
        let crypto = MessageCryptoService.shared
        let publicKey = AccountKeyManager.shared.publicKeyBase64(userId: 2)!
        let original = "  Hola, ¿cómo estás?\n日本語 👋  "
        let translated = "Hello, how are you?"
        let payload = try crypto.encryptForSingleUser(
            plaintext: translated, recipientUserId: 2,
            recipientPublicKeyBase64: publicKey, language: "en",
            originalText: original
        )
        let fields = try JSONSerialization.jsonObject(with: Data(payload.encryptedKey.utf8)) as! [String: String]
        let originalCiphertext = fields["originalContentCiphertext"]!
        let primary = try crypto.decryptMessageForCurrentBackend(
            ciphertextBase64: payload.contentCiphertext,
            encryptedKeyPayload: payload.encryptedKey, userId: 2
        )
        precondition(primary == translated, "Existing primary message must remain readable")
        let decodedOriginal = try crypto.decryptMessageForCurrentBackend(
            ciphertextBase64: originalCiphertext,
            encryptedKeyPayload: payload.encryptedKey, userId: 2
        )
        precondition(decodedOriginal == original, "Original must preserve Unicode and whitespace")
        precondition(!payload.encryptedKey.contains(original), "Envelope must not contain plaintext")
        let packedOriginal = Data(base64Encoded: originalCiphertext)!
        let packedMain = Data(base64Encoded: payload.contentCiphertext)!
        precondition(packedOriginal.prefix(12) != packedMain.prefix(12), "Nonces must differ")
        let legacy = try crypto.encryptForSingleUser(
            plaintext: original, recipientUserId: 2, recipientPublicKeyBase64: publicKey
        )
        let legacyFields = try JSONSerialization.jsonObject(with: Data(legacy.encryptedKey.utf8)) as! [String: String]
        precondition(legacyFields["originalContentCiphertext"] == nil)
        let same = try crypto.encryptForSingleUser(
            plaintext: original, recipientUserId: 2, recipientPublicKeyBase64: publicKey,
            originalText: original
        )
        let sameFields = try JSONSerialization.jsonObject(with: Data(same.encryptedKey.utf8)) as! [String: String]
        precondition(sameFields["originalContentCiphertext"] == nil)
        var tampered = packedOriginal
        tampered[tampered.count - 1] ^= 1
        do {
            _ = try crypto.decryptMessageForCurrentBackend(
                ciphertextBase64: tampered.base64EncodedString(),
                encryptedKeyPayload: payload.encryptedKey, userId: 2
            )
            preconditionFailure("Tampered original must fail authentication")
        } catch {}
        do {
            _ = try crypto.decryptMessageForCurrentBackend(
                ciphertextBase64: originalCiphertext,
                encryptedKeyPayload: payload.encryptedKey, userId: 3
            )
            preconditionFailure("Wrong recipient must not decrypt")
        } catch {}
        print("PASS: primary/original roundtrip, Unicode, independent nonces, legacy messages, identical text, tampering, wrong recipient")
    }
}
