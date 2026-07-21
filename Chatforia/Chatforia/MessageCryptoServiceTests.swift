import XCTest
import CryptoKit
@testable import Chatforia

final class MessageCryptoServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AccountKeyManager.shared.clear(userId: 1)
    }

    override func tearDown() {
        AccountKeyManager.shared.clear(userId: 1)
        super.tearDown()
    }

    func testEncryptThrowsNoRecipientsWhenRecipientsEmpty() {
        XCTAssertThrowsError(
            try MessageCryptoService.shared.encryptMessageForRecipients(
                plaintext: "Hello",
                senderUserId: 1,
                recipients: []
            )
        ) { error in
            XCTAssertEqual(error as? MessageCryptoError, .noRecipients)
        }
    }

    func testEncryptThrowsMissingSenderPublicKeyWhenNoLocalKeysExist() {
        let recipientKeys = try! AccountKeyManager.shared.generateNewAccountKeys()

        let recipient = RecipientKeyContext(
            userId: 2,
            publicKeyBase64: recipientKeys.publicKeyBase64
        )

        XCTAssertThrowsError(
            try MessageCryptoService.shared.encryptMessageForRecipients(
                plaintext: "Hello",
                senderUserId: 1,
                recipients: [recipient]
            )
        ) { error in
            XCTAssertEqual(error as? MessageCryptoError, .missingSenderPublicKey)
        }
    }

    func testEncryptThrowsInvalidRecipientPublicKeyForBadBase64() throws {
        let senderKeys = try AccountKeyManager.shared.generateNewAccountKeys()

        try AccountKeyManager.shared.saveAccountKeys(
            userId: 1,
            publicKeyBase64: senderKeys.publicKeyBase64,
            privateKeyBase64: senderKeys.privateKeyBase64
        )

        let recipient = RecipientKeyContext(
            userId: 2,
            publicKeyBase64: "not-valid-base64"
        )

        XCTAssertThrowsError(
            try MessageCryptoService.shared.encryptMessageForRecipients(
                plaintext: "Hello",
                senderUserId: 1,
                recipients: [recipient]
            )
        )
    }

    func testEncryptCreatesCiphertextAndKeysForSenderAndRecipient() throws {
        let senderKeys = try AccountKeyManager.shared.generateNewAccountKeys()
        let recipientKeys = try AccountKeyManager.shared.generateNewAccountKeys()

        try AccountKeyManager.shared.saveAccountKeys(
            userId: 1,
            publicKeyBase64: senderKeys.publicKeyBase64,
            privateKeyBase64: senderKeys.privateKeyBase64
        )

        let payload = try MessageCryptoService.shared.encryptMessageForRecipients(
            plaintext: "Hello secure world",
            senderUserId: 1,
            recipients: [
                RecipientKeyContext(
                    userId: 2,
                    publicKeyBase64: recipientKeys.publicKeyBase64
                )
            ]
        )

        XCTAssertFalse(payload.ciphertextBase64.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: payload.ciphertextBase64))

        XCTAssertEqual(payload.encryptedKeysByUserId.keys.sorted(), ["1", "2"])
        XCTAssertNotNil(payload.encryptedKeysByUserId["1"])
        XCTAssertNotNil(payload.encryptedKeysByUserId["2"])
    }

    func testEncryptThenDecryptForCurrentUserRoundTrip() throws {
        let senderKeys = try AccountKeyManager.shared.generateNewAccountKeys()
        let recipientKeys = try AccountKeyManager.shared.generateNewAccountKeys()

        try AccountKeyManager.shared.saveAccountKeys(
            userId: 1,
            publicKeyBase64: senderKeys.publicKeyBase64,
            privateKeyBase64: senderKeys.privateKeyBase64
        )

        let payload = try MessageCryptoService.shared.encryptMessageForRecipients(
            plaintext: "Hello encrypted Chatforia",
            senderUserId: 1,
            recipients: [
                RecipientKeyContext(
                    userId: 2,
                    publicKeyBase64: recipientKeys.publicKeyBase64
                )
            ]
        )

        let senderEncryptedKey = try XCTUnwrap(
            payload.encryptedKeysByUserId["1"]
        )

        let decrypted = try MessageCryptoService.shared.decryptMessageForCurrentBackend(
            ciphertextBase64: payload.ciphertextBase64,
            encryptedKeyPayload: senderEncryptedKey,
            userId: 1
        )

        XCTAssertEqual(decrypted, "Hello encrypted Chatforia")
    }

    func testDecryptThrowsForInvalidCiphertextBase64() {
        XCTAssertThrowsError(
            try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: "bad-ciphertext",
                encryptedKeyPayload: "{}",
                userId: 1
            )
        )
    }

    func testDecryptThrowsForInvalidEncryptedKeyPayload() {
        let fakeCiphertext = Data("fake".utf8).base64EncodedString()

        XCTAssertThrowsError(
            try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: fakeCiphertext,
                encryptedKeyPayload: "{bad-json",
                userId: 1
            )
        )
    }

    func testDecryptThrowsForLegacyBase64WrappedKeyWithoutEpk() {
        let fakeCiphertext = Data("fake".utf8).base64EncodedString()
        let fakeWrappedKey = Data("wrapped-key".utf8).base64EncodedString()

        XCTAssertThrowsError(
            try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: fakeCiphertext,
                encryptedKeyPayload: fakeWrappedKey,
                userId: 1
            )
        )
    }
}
