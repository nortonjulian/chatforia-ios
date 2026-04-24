import Foundation

struct VoicemailDTO: Codable, Identifiable, Equatable, Sendable  {
    let id: String
    let userId: Int?
    let phoneNumberId: Int?
    let fromNumber: String
    let toNumber: String
    let audioUrl: String
    let durationSec: Int?
    let transcript: String?
    let transcriptStatus: VoicemailTranscriptStatus
    let isRead: Bool
    let deleted: Bool?
    let createdAt: Date
    let forwardedToEmailAt: Date?
}

struct VoicemailListResponseDTO: Decodable {
    let voicemails: [VoicemailDTO]
}

extension VoicemailDTO {
    var callbackNumber: String? {
        let trimmed = fromNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
