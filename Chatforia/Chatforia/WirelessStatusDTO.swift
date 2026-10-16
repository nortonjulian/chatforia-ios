import Foundation

struct WirelessStatusDTO: Decodable {
    let mode: String
    let state: String
    let low: Bool?
    let exhausted: Bool?
    let expired: Bool?
    let source: WirelessStatusSourceDTO?

    // Optional additive fields for queued eSIM top-ups.
    // Older backend responses remain fully decodable.
    let queuedPacks: [WirelessQueuedPackDTO]?
    let queuedDataMb: Int?
    let totalAvailableDataMb: Int?
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

struct WirelessQueuedPackDTO: Decodable, Identifiable {
    let id: Int
    let addonKind: String?
    let totalDataMb: Int?
    let remainingDataMb: Int?
    let expiresAt: Date?
}
