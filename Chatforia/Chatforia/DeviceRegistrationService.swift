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
