import Foundation

struct DeviceDTO: Codable, Identifiable, Equatable {
    let id: String?
    let userId: Int?
    let deviceId: String
    let name: String?
    let platform: String?
    let publicKey: String
    let keyAlgorithm: String?
    let keyVersion: Int?
    let lastSeenAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

struct DeviceRegisterRequest: Encodable {
    let deviceId: String
    let name: String
    let platform: String
    let publicKey: String
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
