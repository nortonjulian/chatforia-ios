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
    let unlimited: Bool?
    let totalDataMb: Int?
    let remainingDataMb: Int?
    let expiresAt: Date?
    let daysRemaining: Int?

    var isUnlimited: Bool {
        unlimited == true || addonKind?.localizedCaseInsensitiveContains("_unlimited") == true
    }
}

struct WirelessQueuedPackDTO: Decodable, Identifiable {
    let id: Int
    let addonKind: String?
    let unlimited: Bool?
    let totalDataMb: Int?
    let remainingDataMb: Int?
    let expiresAt: Date?

    var isUnlimited: Bool {
        unlimited == true || addonKind?.localizedCaseInsensitiveContains("_unlimited") == true
    }
}
