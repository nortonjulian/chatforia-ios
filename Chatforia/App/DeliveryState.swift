import Foundation

public enum DeliveryState: String, Codable {
    case pending
    case sending
    case sent
    case delivered
    case read
    case failed
}
