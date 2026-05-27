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

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var localizedTitle: String {
        appText(titleKey, languageCode: appLanguage)
    }
}
