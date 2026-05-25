import Foundation

enum CallsSegment: String, CaseIterable, Identifiable {
    case recents
    case voicemail

    var id: String {
        localizedTitle
    }

    var localizedTitle: String {
        switch self {
        case .recents:
            return String(localized: "calls.recents")

        case .voicemail:
            return String(localized: "calls.voicemail")
        }
    }
}
