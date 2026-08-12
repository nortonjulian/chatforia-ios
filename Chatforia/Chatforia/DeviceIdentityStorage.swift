import Foundation
import CryptoKit

/*
 * Compatibility facade for linked-device code.
 *
 * DeviceKeyManager is the single source of truth for this installation's
 * device ID and Curve25519 identity. Keeping this facade avoids two
 * independent Keychain identities representing one physical iPhone.
 */
final class DeviceIdentityStorage {
    static let shared = DeviceIdentityStorage()

    private init() {}

    private let keyManager = DeviceKeyManager.shared

    func getOrCreateDeviceId() -> String {
        keyManager.getOrCreateDeviceId()
    }

    func getOrCreatePrivateKey()
        throws -> Curve25519.KeyAgreement.PrivateKey
    {
        try keyManager.getOrCreatePrivateKey()
    }

    func publicKeyBase64() throws -> String {
        try keyManager.publicKeyBase64()
    }

    func privateKey()
        throws -> Curve25519.KeyAgreement.PrivateKey
    {
        try keyManager.privateKey()
    }

    func currentDeviceName() -> String {
        keyManager.currentDeviceName()
    }

    func currentPlatform() -> String {
        keyManager.currentPlatform()
    }

    func clear() {
        keyManager.clear()
    }
}
