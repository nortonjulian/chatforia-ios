import Foundation

enum NumberPickMode: String, CaseIterable, Identifiable {
    case free
    case buy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Available number"
        case .buy: return "Buy a number"
        }
    }

    var subtitle: String {
        switch self {
        case .free: return "Lease a Chatforia number from the free pool."
        case .buy: return "Choose a number from Chatforia inventory."
        }
    }

    var forSale: Bool {
        switch self {
        case .free: return false
        case .buy: return true
        }
    }
}
