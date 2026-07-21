import Foundation
import Combine

struct DeviceReplacementPrompt: Identifiable {
    let id = UUID()
    let message: String
    let existingDevices: [DeviceDTO]
}

@MainActor
final class DeviceReplacementCoordinator: ObservableObject {
    static let shared = DeviceReplacementCoordinator()

    @Published var prompt: DeviceReplacementPrompt?

    private init() {}

    func present(
        message: String,
        existingDevices: [DeviceDTO]
    ) {
        prompt = DeviceReplacementPrompt(
            message: message,
            existingDevices: existingDevices
        )
    }

    func clear() {
        prompt = nil
    }
}

struct DeviceReplacementRequiredError: LocalizedError {
    let code: String
    let existingDevices: [DeviceDTO]
    let message: String

    var errorDescription: String? {
        message
    }
}

struct DeviceRegistrationErrorResponse: Decodable {
    let error: String?
    let message: String?
    let code: String?
    let existingDevices: [DeviceDTO]?
}

final class DeviceRegistrationService {
    static let shared = DeviceRegistrationService()
    private init() {}

    static func replacementError(
        from apiError: APIError
    ) -> DeviceReplacementRequiredError? {
        guard
            case .server(
                let status,
                let responseBody
            ) = apiError,
            status == 409,
            let responseBody,
            let responseData =
                responseBody.data(using: .utf8),
            let decoded =
                try? JSONDecoder().decode(
                    DeviceRegistrationErrorResponse.self,
                    from: responseData
                ),
            let code = decoded.code,
            code == "DEVICE_REPLACEMENT_REQUIRED"
                || code == "DEVICE_REPLACEMENT_TARGET_STALE"
        else {
            return nil
        }

        return DeviceReplacementRequiredError(
            code: code,
            existingDevices:
                decoded.existingDevices ?? [],
            message:
                decoded.message
                ?? decoded.error
                ?? "Device replacement confirmation is required."
        )
    }

    func ensureCurrentDeviceRegistered(
        userId: Int,
        token: String,
        replaceDeviceId: String? = nil
    ) async throws -> DeviceDTO {
        _ = userId

        let keyManager = DeviceKeyManager.shared

        let request = DeviceRegisterRequest(
            deviceId: keyManager.getOrCreateDeviceId(),
            name: keyManager.currentDeviceName(),
            platform: keyManager.currentPlatform(),
            publicKey: try keyManager.publicKeyBase64(),
            keyAlgorithm: "curve25519",
            keyVersion: 1,
            replaceExistingDevice:
                replaceDeviceId == nil ? nil : true,
            replaceDeviceId: replaceDeviceId
        )

        let body = try JSONEncoder().encode(request)

        do {
            let response: DeviceRegisterResponse =
                try await APIClient.shared.send(
                    APIRequest(
                        path: "devices/register",
                        method: .POST,
                        body: body,
                        requiresAuth: true
                    ),
                    token: token
                )

            if replaceDeviceId != nil {
                await MainActor.run {
                    DeviceReplacementCoordinator.shared.clear()
                }
            }

            return response.device
        } catch let apiError as APIError {
            guard
                let replacementError =
                    Self.replacementError(from: apiError)
            else {
                throw apiError
            }

            await MainActor.run {
                DeviceReplacementCoordinator.shared.present(
                    message: replacementError.message,
                    existingDevices:
                        replacementError.existingDevices
                )
            }

            throw replacementError
        }
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
            debugLog("⚠️ device heartbeat failed:", error)
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
        wrappedAccountKeyAlgo: String = "x25519-aesgcm",
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
            let publicKey: String
            let keyAlgorithm: String
            let keyVersion: Int
            let platform: String
            let name: String
        }

        struct RegisterPushTokenResponse: Decodable {
            let success: Bool?
            let device: DeviceDTO?
        }

        let keyManager = DeviceKeyManager.shared

        let body = try JSONEncoder().encode(
            RegisterPushTokenRequest(
                deviceId: keyManager.getOrCreateDeviceId(),
                pushToken: pushToken,
                pushProvider: provider,
                publicKey: try keyManager.publicKeyBase64(),
                keyAlgorithm: "curve25519",
                keyVersion: 1,
                platform: keyManager.currentPlatform(),
                name: keyManager.currentDeviceName()
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
