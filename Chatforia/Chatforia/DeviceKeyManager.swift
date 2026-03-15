import Foundation
import CryptoKit

#if canImport(UIKit)
import UIKit
#endif

final class DeviceKeyManager {
    static let shared = DeviceKeyManager()
    private init() {}

    private let service = "com.chatforia.devicekeys"
    private let deviceIdAccount = "installation.deviceId"
    private let privateKeyAccount = "installation.curve25519.private"

    func getOrCreateDeviceId() -> String {
        if let existing = KeychainHelper.read(service: service, account: deviceIdAccount),
           let id = String(data: existing, encoding: .utf8),
           !id.isEmpty {
            return id
        }

        let newId = UUID().uuidString.lowercased()
        _ = KeychainHelper.save(
            data: Data(newId.utf8),
            service: service,
            account: deviceIdAccount
        )
        return newId
    }

    func getOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let data = KeychainHelper.read(service: service, account: privateKeyAccount) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let raw = privateKey.rawRepresentation

        let ok = KeychainHelper.save(
            data: raw,
            service: service,
            account: privateKeyAccount
        )

        if !ok {
            throw NSError(
                domain: "DeviceKeyManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save device private key to Keychain"]
            )
        }

        return privateKey
    }

    func publicKeyBase64() throws -> String {
        let privateKey = try getOrCreatePrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        return publicKeyData.base64EncodedString()
    }

    func privateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try getOrCreatePrivateKey()
    }

    func currentDeviceName() -> String {
        #if canImport(UIKit)
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "iPhone" : name
        #else
        return "Apple Device"
        #endif
    }

    func currentPlatform() -> String {
        #if canImport(UIKit)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        return "iOS"
        #endif
    }
}
