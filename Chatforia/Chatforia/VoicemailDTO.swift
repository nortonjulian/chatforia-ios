import Foundation

struct VoicemailDTO: Codable, Identifiable, Equatable, Sendable {
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

    // App-to-app voicemail identity supplied by the backend.
    let callerUserId: Int?
    let displayName: String?
    let username: String?
}

struct VoicemailListResponseDTO: Decodable {
    let voicemails: [VoicemailDTO]
}

extension VoicemailDTO {
    var secureAudioURLString: String {
        AppEnvironment.apiBaseURL
            .appendingPathComponent("voicemail")
            .appendingPathComponent(id)
            .appendingPathComponent("audio")
            .absoluteString
    }

    var resolvedCallerName: String? {
        if let displayName = cleaned(displayName) {
            return displayName
        }

        if let username = cleaned(username) {
            return "@\(username)"
        }

        return nil
    }

    var callbackNumber: String? {
        // App callers must use callerUserId instead of dialing app:user_3.
        guard callerUserId == nil else {
            return nil
        }

        return cleaned(fromNumber)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }
}
