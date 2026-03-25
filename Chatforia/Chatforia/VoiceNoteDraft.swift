import Foundation

struct VoiceNoteDraft: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    let durationSec: Double
    let createdAt: Date = Date()
}
