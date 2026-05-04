import Foundation

final class DeviceRegistrationService {
    static let shared = DeviceRegistrationService()
    private init() {}

    func ensureCurrentDeviceRegistered(userId: Int, token: String) async throws -> DeviceDTO {
        let keyManager = DeviceKeyManager.shared

        let request = DeviceRegisterRequest(
            deviceId: keyManager.getOrCreateDeviceId(),
            name: keyManager.currentDeviceName(),
            platform: keyManager.currentPlatform(),
            publicKey: try keyManager.publicKeyBase64(),
            keyAlgorithm: "curve25519",
            keyVersion: 1
        )

        let body = try JSONEncoder().encode(request)

        let response: DeviceRegisterResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/register",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return response.device
    }

    func fetchMyDevices(token: String) async throws -> [DeviceDTO] {
        let response: DeviceListResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/mine",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
        return response.items
    }

    func fetchPublicDevices(for userId: Int, token: String) async throws -> [DeviceDTO] {
        let response: DeviceListResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/user/\(userId)/public",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
        return response.items
    }

    func heartbeat(token: String) async {
        do {
            let req = DeviceHeartbeatRequest(
                deviceId: DeviceKeyManager.shared.getOrCreateDeviceId()
            )
            let body = try JSONEncoder().encode(req)

            let _: DeviceHeartbeatResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "devices/heartbeat",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )
        } catch {
            print("⚠️ device heartbeat failed:", error)
        }
    }

    func registerPushToken(_ pushToken: String, token: String) async throws {
        try await registerPushToken(pushToken, provider: "apns", token: token)
    }

    func registerVoIPPushToken(_ pushToken: String, token: String) async throws {
        try await registerPushToken(pushToken, provider: "apns_voip", token: token)
    }
    
    func fetchPendingPairingDevices(token: String) async throws -> [DeviceDTO] {
        let response: DeviceListResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/pending",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
        return response.items
    }

    func approvePairing(
        deviceId: String,
        wrappedAccountKey: String,
        wrappedAccountKeyAlgo: String = "x25519-xsalsa20poly1305",
        wrappedAccountKeyVer: Int = 1,
        token: String
    ) async throws -> DeviceDTO {
        let payload = DevicePairingApproveRequest(
            deviceId: deviceId,
            wrappedAccountKey: wrappedAccountKey,
            wrappedAccountKeyAlgo: wrappedAccountKeyAlgo,
            wrappedAccountKeyVer: wrappedAccountKeyVer
        )

        let body = try JSONEncoder().encode(payload)

        let response: DeviceRegisterResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/approve",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return response.device
    }

    func rejectPairing(deviceId: String, token: String) async throws -> DeviceDTO {
        let payload = DevicePairingRejectRequest(deviceId: deviceId)
        let body = try JSONEncoder().encode(payload)

        let response: DeviceRegisterResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/reject",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return response.device
    }

    func fetchPairingStatus(deviceId: String, token: String) async throws -> DeviceDTO {
        let response: DevicePairingStatusResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/status/\(deviceId)",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.device
    }
    
    func approvePairingRequest(
        for pendingDevice: DeviceDTO,
        token: String
    ) async throws -> DeviceDTO {
        guard let deviceId = pendingDevice.deviceId,
              let browserPublicKey = pendingDevice.publicKey
        else {
            throw NSError(
                domain: "DeviceRegistrationService",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Pending device is missing deviceId or publicKey"]
            )
        }

        let wrapped = try DevicePairingCrypto.shared.wrapAccountKeysForBrowser(
            browserPublicKeyBase64: browserPublicKey
        )

        let request = DevicePairingApproveRequest(
            deviceId: deviceId,
            wrappedAccountKey: try encodeWrappedPayload(wrapped),
            wrappedAccountKeyAlgo: wrapped.algorithm,
            wrappedAccountKeyVer: wrapped.version
        )

        let body = try JSONEncoder().encode(request)

        let response: DeviceRegisterResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/approve",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return response.device
    }

    private func encodeWrappedPayload(_ payload: WrappedAccountKeyPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "DeviceRegistrationService",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode wrapped payload"]
            )
        }
        return string
    }

    private func registerPushToken(_ pushToken: String, provider: String, token: String) async throws {
        struct RegisterPushTokenRequest: Encodable {
            let deviceId: String
            let pushToken: String
            let pushProvider: String
        }

        struct RegisterPushTokenResponse: Decodable {
            let success: Bool?
            let device: DeviceDTO?
        }

        let body = try JSONEncoder().encode(
            RegisterPushTokenRequest(
                deviceId: DeviceKeyManager.shared.getOrCreateDeviceId(),
                pushToken: pushToken,
                pushProvider: provider
            )
        )

        let _: RegisterPushTokenResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/push-token",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }
}
