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

    var label: String {
        switch self {

        case .idle:
            return String(localized: "calls.idle")

        case .fetchingToken:
            return String(localized: "calls.preparing")

        case .dialing(let destination):
            return String(
                format: String(localized: "calls.callingDestination"),
                destination.displayName
            )

        case .ringingIncoming(let name):
            return String(
                format: String(localized: "calls.incomingCalling"),
                name
            )

        case .connecting(let name):
            return String(
                format: String(localized: "calls.connecting"),
                name
            )

        case .active(let name):
            return String(
                format: String(localized: "calls.inCallWith"),
                name
            )

        case .ended:
            return String(localized: "calls.ended")

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