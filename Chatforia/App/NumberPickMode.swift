import Foundation

enum NumberPickMode: String, CaseIterable, Identifiable {
    case free
    case premium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Available number"
        case .premium: return "Premium number 🔒"
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return "Free number that may be lost after inactivity."
        case .premium:
            return "Keep and protect your number (no recycling)"
        }
    }

    var forSale: Bool {
        switch self {
        case .free: return false
        case .premium: return true
        }
    }

    var requiresPremium: Bool {
        switch self {
        case .free: return false
        case .premium: return true
        }
    }
}
