import Foundation

enum CallsSegment: String, CaseIterable, Identifiable {
    case recents
    case voicemail

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .recents:
            return "calls.recents"

        case .voicemail:
            return "calls.voicemail"
        }
    }

    var localizedTitle: String {
        String(localized: String.LocalizationValue(titleKey))
    }
}
