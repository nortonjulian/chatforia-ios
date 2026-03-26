import Foundation

enum CallsSegment: String, CaseIterable, Identifiable {
    case recents = "Recents"
    case voicemail = "Voicemail"

    var id: String { rawValue }
}
