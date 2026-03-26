import Foundation

enum VoicemailTranscriptStatus: String, Codable, Equatable {
    case pending = "PENDING"
    case complete = "COMPLETE"
    case failed = "FAILED"
}
