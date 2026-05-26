import Foundation

enum NumberPickMode: String, CaseIterable, Identifiable {
    case free
    case premium

    var id: String { rawValue }

    var title: String {
        switch self {

        case .free:
            return String(localized: "phoneNumber.availableNumber")

        case .premium:
            return String(localized: "phoneNumber.premiumNumber")
        }
    }

    var subtitle: String {
        switch self {

        case .free:
            return String(
                localized:
                "phoneNumber.freeNumberSubtitle"
            )

        case .premium:
            return String(
                localized:
                "phoneNumber.premiumNumberSubtitle"
            )
        }
    }

    var forSale: Bool {
        switch self {
        case .free:
            return false

        case .premium:
            return true
        }
    }

    var requiresPremium: Bool {
        switch self {
        case .free:
            return false

        case .premium:
            return true
        }
    }
}