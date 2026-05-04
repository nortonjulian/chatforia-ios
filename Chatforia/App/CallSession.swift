import Foundation

struct CallSession: Equatable, Identifiable {
    let id: UUID
    let destination: CallDestination
    let direction: CallDirection

    var status: CallLifecycleStatus
    let startedAt: Date
    var answeredAt: Date?
    var endedAt: Date?

    var callSid: String?
    var displayName: String
    var remoteIdentity: String?
    var chatRoomId: Int?
    var backendCallId: Int?

    var isMuted: Bool
    var isSpeakerOn: Bool
    var isVideo: Bool

    var durationSec: Int? {
        guard let answeredAt, let endedAt else { return nil }
        return max(0, Int(endedAt.timeIntervalSince(answeredAt)))
    }
}
