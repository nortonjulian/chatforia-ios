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

    var participants: [CallParticipant] = []
    var canAddParticipant: Bool {
        !isVideo && participants.filter { $0.status == .ringing || $0.status == .joined }.count < 3
    }

    var durationSec: Int? {
        guard let answeredAt, let endedAt else { return nil }
        return max(0, Int(endedAt.timeIntervalSince(answeredAt)))
    }
}

struct CallParticipant: Equatable, Identifiable, Codable {
    let id: Int?
    let userId: Int
    var role: String
    var status: CallParticipantStatus
    var displayName: String?
    var username: String?
    var avatarUrl: String?
}

enum CallParticipantStatus: String, Codable, Equatable {
    case ringing = "RINGING"
    case joined = "JOINED"
    case left = "LEFT"
    case declined = "DECLINED"
}