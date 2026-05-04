import Foundation

enum ReportReason: String, CaseIterable, Identifiable, Codable {
    case harassment = "harassment"
    case threats = "threats"
    case hate = "hate"
    case sexualContent = "sexual_content"
    case spamScam = "spam_scam"
    case impersonation = "impersonation"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment:
            return "Harassment"
        case .threats:
            return "Threats"
        case .hate:
            return "Hate or abusive conduct"
        case .sexualContent:
            return "Sexual content"
        case .spamScam:
            return "Spam or scam"
        case .impersonation:
            return "Impersonation"
        case .other:
            return "Other"
        }
    }
}
