import Foundation

struct WirelessStatusDTO: Decodable {
    let mode: String
    let state: String
    let low: Bool?
    let exhausted: Bool?
    let expired: Bool?
    let source: WirelessStatusSourceDTO?
}

struct WirelessStatusSourceDTO: Decodable {
    let type: String?
    let id: Int?
    let addonKind: String?
    let totalDataMb: Int?
    let remainingDataMb: Int?
    let expiresAt: Date?
    let daysRemaining: Int?
}

