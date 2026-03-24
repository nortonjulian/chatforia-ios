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
        case .idle: return "Idle"
        case .fetchingToken: return "Preparing call…"
        case .dialing(let destination): return "Calling \(destination.displayName)…"
        case .ringingIncoming(let name): return "\(name) is calling…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .active(let name): return "In call with \(name)"
        case .ended: return "Call ended"
        case .failed(let message): return message
        }
    }

    var isInCallFlow: Bool {
        switch self {
        case .fetchingToken, .dialing, .ringingIncoming, .connecting, .active:
            return true
        case .idle, .ended, .failed:
            return false
        }
    }
}
