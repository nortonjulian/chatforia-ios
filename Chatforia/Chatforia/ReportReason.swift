import Foundation

enum ReportReason: String, CaseIterable, Identifiable {
    case harassment
    case threats
    case hate
    case sexualContent = "sexual_content"
    case spamScam = "spam_scam"
    case impersonation
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment: return "Harassment"
        case .threats: return "Threats"
        case .hate: return "Hate or abusive conduct"
        case .sexualContent: return "Sexual content"
        case .spamScam: return "Spam or scam"
        case .impersonation: return "Impersonation"
        case .other: return "Other"
        }
    }
}
