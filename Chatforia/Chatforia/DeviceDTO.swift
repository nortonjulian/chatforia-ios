import Foundation

// MARK: - Core Device DTO

struct DeviceDTO: Codable, Identifiable, Equatable {
    let id: String?
    let userId: Int?
    let deviceId: String?
    let name: String?
    let platform: String?
    let publicKey: String?
    let keyAlgorithm: String?
    let keyVersion: Int?
    let isPrimary: Bool?

    // 🔐 Pairing / E2EE fields
    let wrappedAccountKey: String?
    let wrappedAccountKeyAlgo: String?
    let wrappedAccountKeyVer: Int?

    let pairingStatus: String?
    let pairingRequestedAt: Date?
    let pairingApprovedAt: Date?
    let pairingRejectedAt: Date?

    // 📅 Metadata
    let lastSeenAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let revokedAt: Date?
}

struct DeviceRegisterRequest: Encodable {
    let deviceId: String
    let name: String
    let platform: String
    let publicKey: String?
    let keyAlgorithm: String
    let keyVersion: Int
}

struct DeviceRegisterResponse: Decodable {
    let device: DeviceDTO
}

struct DeviceListResponse: Decodable {
    let items: [DeviceDTO]
}

struct DeviceHeartbeatRequest: Encodable {
    let deviceId: String
}

struct DeviceHeartbeatResponse: Decodable {
    let device: DeviceDTO
}


struct DevicePairingRequestPayload: Encodable {
    let deviceId: String
    let name: String
    let platform: String
    let publicKey: String
    let keyAlgorithm: String
    let keyVersion: Int
}

struct DevicePairingApproveRequest: Encodable {
    let deviceId: String
    let wrappedAccountKey: String
    let wrappedAccountKeyAlgo: String
    let wrappedAccountKeyVer: Int
}

struct DevicePairingRejectRequest: Encodable {
    let deviceId: String
}

struct DevicePairingStatusResponse: Decodable {
    let device: DeviceDTO
}
