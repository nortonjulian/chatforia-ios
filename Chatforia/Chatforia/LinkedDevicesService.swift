import SwiftUI
import Combine
import Foundation
import CryptoKit

struct LinkedDeviceDTO: Codable, Identifiable {
    let id: String?
    let userId: Int?
    let deviceId: String
    let name: String?
    let platform: String?
    let publicKey: String?
    let keyAlgorithm: String?
    let keyVersion: Int?
    let isPrimary: Bool?
    let pairingStatus: String?
    let wrappedAccountKey: String?
    let wrappedAccountKeyAlgo: String?
    let wrappedAccountKeyVer: Int?
    let createdAt: String?
    let updatedAt: String?
    let lastSeenAt: String?
    let revokedAt: String?
}

struct LinkedDevicesResponse: Decodable {
    let items: [LinkedDeviceDTO]?
    let devices: [LinkedDeviceDTO]?

    var resolvedItems: [LinkedDeviceDTO] {
        if let items, !items.isEmpty { return items }
        return devices ?? []
    }
}

struct LinkedDeviceResponse: Decodable {
    let device: LinkedDeviceDTO?
}

struct DeviceIdRequest: Encodable {
    let deviceId: String
}

struct LinkedDeviceRegisterRequest: Encodable {
    let deviceId: String
    let name: String
    let platform: String
    let publicKey: String
    let keyAlgorithm: String
    let keyVersion: Int
}

struct ApproveDeviceRequest: Encodable {
    let deviceId: String
    let wrappedAccountKey: String
    let wrappedAccountKeyAlgo: String
    let wrappedAccountKeyVer: Int
}

final class LinkedDevicesService {
    static let shared = LinkedDevicesService()
    private init() {}

    func fetchMine(token: String) async throws -> [LinkedDeviceDTO] {
        let response: LinkedDevicesResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/mine",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.resolvedItems
    }

    func fetchPendingPairing(token: String) async throws -> [LinkedDeviceDTO] {
        let response: LinkedDevicesResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/pending",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.resolvedItems
    }

    func requestPairing(
        token: String,
        request: LinkedDeviceRegisterRequest
    ) async throws {
        let body = try JSONEncoder().encode(request)

        let _: LinkedDeviceResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/request",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func approve(
        token: String,
        deviceId: String,
        wrappedAccountKey: String
    ) async throws {
        let body = try JSONEncoder().encode(
            ApproveDeviceRequest(
                deviceId: deviceId,
                wrappedAccountKey: wrappedAccountKey,
                wrappedAccountKeyAlgo: "x25519-xsalsa20poly1305",
                wrappedAccountKeyVer: 1
            )
        )

        let _: LinkedDeviceResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/approve",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func reject(
        token: String,
        deviceId: String
    ) async throws {
        let body = try JSONEncoder().encode(
            DeviceIdRequest(deviceId: deviceId)
        )

        let _: LinkedDeviceResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/reject",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func revoke(
        token: String,
        deviceId: String
    ) async throws {
        let body = try JSONEncoder().encode(
            DeviceIdRequest(deviceId: deviceId)
        )

        let _: LinkedDeviceResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/revoke",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func fetchPairingStatus(
        token: String,
        deviceId: String
    ) async throws -> LinkedDeviceDTO? {
        let response: LinkedDeviceResponse = try await APIClient.shared.send(
            APIRequest(
                path: "devices/pairing/status/\(deviceId)",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.device
    }
}
