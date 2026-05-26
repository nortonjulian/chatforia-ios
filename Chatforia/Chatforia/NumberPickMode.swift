import Foundation

enum NumberPickMode: String, CaseIterable, Identifiable {
    case free
    case premium

    var id: String { rawValue }

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var title: String {
        switch self {

        case .free:
            return appText(
                "phoneNumber.availableNumber",
                languageCode: appLanguage
            )

        case .premium:
            return appText(
                "phoneNumber.premiumNumber",
                languageCode: appLanguage
            )
        }
    }

    var subtitle: String {
        switch self {

        case .free:
            return appText(
                "phoneNumber.freeNumberSubtitle",
                languageCode: appLanguage
            )

        case .premium:
            return appText(
                "phoneNumber.premiumNumberSubtitle",
                languageCode: appLanguage
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
