import Foundation

enum CallLifecycleStatus: String, Codable, Equatable {
    case idle
    case starting
    case ringing
    case connecting
    case active
    case ending
    case ended
    case failed
    case missed
    case declined
}
