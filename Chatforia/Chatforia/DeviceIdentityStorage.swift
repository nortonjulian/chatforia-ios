import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

final class DeviceIdentityStorage {
    static let shared = DeviceIdentityStorage()
    private init() {}

    private let service = "com.chatforia.deviceidentity"
    private let deviceIdAccount = "device.id"
    private let privateKeyAccount = "device.curve25519.private"

    func getOrCreateDeviceId() -> String {
        if let data = KeychainHelper.read(service: service, account: deviceIdAccount),
           let id = String(data: data, encoding: .utf8),
           !id.isEmpty {
            return id
        }

        let id = UUID().uuidString.lowercased()

        _ = KeychainHelper.save(
            data: Data(id.utf8),
            service: service,
            account: deviceIdAccount
        )

        return id
    }

    func getOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let data = KeychainHelper.read(service: service, account: privateKeyAccount) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()

        let ok = KeychainHelper.save(
            data: privateKey.rawRepresentation,
            service: service,
            account: privateKeyAccount
        )

        if !ok {
            throw NSError(
                domain: "DeviceIdentityStorage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save device identity key"]
            )
        }

        return privateKey
    }

    func publicKeyBase64() throws -> String {
        let privateKey = try getOrCreatePrivateKey()
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
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

    func clear() {
        _ = KeychainHelper.delete(service: service, account: deviceIdAccount)
        _ = KeychainHelper.delete(service: service, account: privateKeyAccount)
    }
}
