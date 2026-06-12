import Foundation

enum CallState: Equatable {
    case idle
    case fetchingToken
    case dialing(CallDestination)
    case ringingIncoming(String)
    case connecting(String)
    case active(String)
    case ended
    case failed(String)
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var label: String {
        switch self {

        case .idle:
            return appText(
                "calls.idle",
                languageCode: appLanguage
            )

        case .fetchingToken:
            return appText(
                "calls.preparing",
                languageCode: appLanguage
            )

        case .dialing(let destination):
            return String(
                format: appText(
                    "calls.callingDestination",
                    languageCode: appLanguage
                ),
                destination.displayName
            )

        case .ringingIncoming(let name):
            return String(
                format: appText(
                    "calls.incomingCalling",
                    languageCode: appLanguage
                )
                .replacingOccurrences(of: "{caller}", with: name)
            )

        case .connecting(let name):
            return String(
                format: appText(
                    "calls.connecting",
                    languageCode: appLanguage
                ),
                name
            )

        case .active(let name):
            return String(
                format: appText(
                    "calls.inCallWith",
                    languageCode: appLanguage
                ),
                name
            )

        case .ended:
            return appText(
                "calls.ended",
                languageCode: appLanguage
            )

        case .failed(let message):
            return message
        }
    }

    var isInCallFlow: Bool {
        switch self {
        case .fetchingToken,
             .dialing,
             .ringingIncoming,
             .connecting,
             .active:
            return true

        case .idle,
             .ended,
             .failed:
            return false
        }
    }
}
