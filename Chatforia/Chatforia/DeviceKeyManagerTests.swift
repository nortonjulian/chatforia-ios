import XCTest
import CryptoKit
@testable import Chatforia

final class DeviceKeyManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DeviceKeyManager.shared.clear()
    }

    override func tearDown() {
        DeviceKeyManager.shared.clear()
        super.tearDown()
    }

    func testGetOrCreateDeviceIdReturnsNonEmptyId() {
        let deviceId = DeviceKeyManager.shared.getOrCreateDeviceId()

        XCTAssertFalse(deviceId.isEmpty)
    }

    func testGetOrCreateDeviceIdPersistsSameId() {
        let first = DeviceKeyManager.shared.getOrCreateDeviceId()
        let second = DeviceKeyManager.shared.getOrCreateDeviceId()

        XCTAssertEqual(first, second)
    }

    func testClearCreatesNewDeviceIdNextTime() {
        let first = DeviceKeyManager.shared.getOrCreateDeviceId()

        DeviceKeyManager.shared.clear()

        let second = DeviceKeyManager.shared.getOrCreateDeviceId()

        XCTAssertNotEqual(first, second)
    }

    func testGetOrCreatePrivateKeyPersistsSameKey() throws {
        let first = try DeviceKeyManager.shared.getOrCreatePrivateKey()
        let second = try DeviceKeyManager.shared.getOrCreatePrivateKey()

        XCTAssertEqual(
            first.rawRepresentation,
            second.rawRepresentation
        )
    }

    func testPublicKeyBase64IsValidBase64() throws {
        let publicKey = try DeviceKeyManager.shared.publicKeyBase64()

        XCTAssertFalse(publicKey.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: publicKey))
    }

    func testPrivateKeyReturnsValidPrivateKey() throws {
        let privateKey = try DeviceKeyManager.shared.privateKey()

        XCTAssertFalse(privateKey.rawRepresentation.isEmpty)
    }

    func testCurrentDeviceNameIsNotEmpty() {
        let name = DeviceKeyManager.shared.currentDeviceName()

        XCTAssertFalse(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testCurrentPlatformIsNotEmpty() {
        let platform = DeviceKeyManager.shared.currentPlatform()

        XCTAssertFalse(platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
