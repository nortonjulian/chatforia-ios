import Foundation

struct CallRecordDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let roomId: Int?
    let callerId: Int
    let calleeId: Int
    let mode: String
    let status: String
    let twilioCallSid: String?
    let durationSec: Int?
    let endReason: String?
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let caller: CallUserSummaryDTO?
    let callee: CallUserSummaryDTO?
    let hasVoicemail: Bool?
    let voicemailId: String?
}

struct CallUserSummaryDTO: Decodable, Equatable {
    let id: Int
    let username: String?
    let displayName: String?
    let avatarUrl: String?
}
