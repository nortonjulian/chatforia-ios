import XCTest
import CryptoKit
@testable import Chatforia

final class DevicePairingCryptoTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AccountKeyManager.shared.clear(userId: 1)
    }

    override func tearDown() {
        AccountKeyManager.shared.clear(userId: 1)
        super.tearDown()
    }

    func testWrapThrowsWhenAccountKeysMissing() {
        let browserKey = Curve25519.KeyAgreement.PrivateKey()
        let browserPublicKey =
            browserKey.publicKey.rawRepresentation.base64EncodedString()

        XCTAssertThrowsError(
            try DevicePairingCrypto.shared.wrapAccountKeysForBrowser(
                browserPublicKeyBase64: browserPublicKey
            )
        ) { error in
            XCTAssertEqual(
                error as? DevicePairingCryptoError,
                .missingAccountKeys
            )
        }
    }

    func testWrapThrowsForInvalidBrowserPublicKey() throws {

        let keys = try AccountKeyManager.shared.generateNewAccountKeys()

        try AccountKeyManager.shared.saveAccountKeys(
            userId: 1,
            publicKeyBase64: keys.publicKeyBase64,
            privateKeyBase64: keys.privateKeyBase64
        )

        XCTAssertThrowsError(
            try DevicePairingCrypto.shared.wrapAccountKeysForBrowser(
                browserPublicKeyBase64: "not-valid-base64"
            )
        ) { error in
            XCTAssertEqual(
                error as? DevicePairingCryptoError,
                .invalidBrowserPublicKey
            )
        }
    }

    func testWrapCreatesValidPayload() throws {

        let accountKeys = try AccountKeyManager.shared.generateNewAccountKeys()

        try AccountKeyManager.shared.saveAccountKeys(
            userId: 1,
            publicKeyBase64: accountKeys.publicKeyBase64,
            privateKeyBase64: accountKeys.privateKeyBase64
        )

        let browserKey = Curve25519.KeyAgreement.PrivateKey()

        let payload =
            try DevicePairingCrypto.shared.wrapAccountKeysForBrowser(
                browserPublicKeyBase64:
                    browserKey.publicKey
                    .rawRepresentation
                    .base64EncodedString()
            )

        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.algorithm, "x25519-aesgcm")

        XCTAssertFalse(payload.senderPublicKey.isEmpty)
        XCTAssertFalse(payload.nonce.isEmpty)
        XCTAssertFalse(payload.ciphertext.isEmpty)

        XCTAssertNotNil(Data(base64Encoded: payload.nonce))
        XCTAssertNotNil(Data(base64Encoded: payload.ciphertext))
    }

    func testWrapThenUnwrapRoundTrip() throws {

        let accountKeys = try AccountKeyManager.shared.generateNewAccountKeys()

        try AccountKeyManager.shared.saveAccountKeys(
            userId: 1,
            publicKeyBase64: accountKeys.publicKeyBase64,
            privateKeyBase64: accountKeys.privateKeyBase64
        )

        let browserPrivateKey =
            Curve25519.KeyAgreement.PrivateKey()

        let wrapped =
            try DevicePairingCrypto.shared.wrapAccountKeysForBrowser(
                browserPublicKeyBase64:
                    browserPrivateKey.publicKey
                    .rawRepresentation
                    .base64EncodedString()
            )

        let unwrapped =
            try DevicePairingCrypto.shared
                .unwrapAccountKeysFromBrowserPayload(
                    wrapped: wrapped,
                    browserPrivateKey: browserPrivateKey
                )

        XCTAssertEqual(
            unwrapped.publicKey,
            accountKeys.publicKeyBase64
        )

        XCTAssertEqual(
            unwrapped.privateKey,
            accountKeys.privateKeyBase64
        )
    }

    func testUnwrapThrowsForInvalidNonce() throws {

        let browserKey = Curve25519.KeyAgreement.PrivateKey()

        let payload = WrappedAccountKeyPayload(
            version: 1,
            algorithm: "x25519-aesgcm",
            senderPublicKey:
                browserKey.publicKey
                .rawRepresentation
                .base64EncodedString(),
            nonce: "bad-base64",
            ciphertext:
                Data("ciphertext".utf8)
                .base64EncodedString()
        )

        XCTAssertThrowsError(
            try DevicePairingCrypto.shared
                .unwrapAccountKeysFromBrowserPayload(
                    wrapped: payload,
                    browserPrivateKey: browserKey
                )
        ) { error in
            XCTAssertEqual(
                error as? DevicePairingCryptoError,
                .invalidNonce
            )
        }
    }

    func testUnwrapThrowsForInvalidCiphertext() throws {

        let browserKey = Curve25519.KeyAgreement.PrivateKey()

        let payload = WrappedAccountKeyPayload(
            version: 1,
            algorithm: "x25519-aesgcm",
            senderPublicKey:
                browserKey.publicKey
                .rawRepresentation
                .base64EncodedString(),
            nonce: Data(repeating: 1, count: 12)
                .base64EncodedString(),
            ciphertext: "bad-base64"
        )

        XCTAssertThrowsError(
            try DevicePairingCrypto.shared
                .unwrapAccountKeysFromBrowserPayload(
                    wrapped: payload,
                    browserPrivateKey: browserKey
                )
        ) { error in
            XCTAssertEqual(
                error as? DevicePairingCryptoError,
                .invalidCiphertext
            )
        }
    }
}
