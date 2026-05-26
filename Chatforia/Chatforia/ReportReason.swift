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
            return String(localized: "report.harassment")

        case .threats:
            return String(localized: "report.threats")

        case .hate:
            return String(localized: "report.hate")

        case .sexualContent:
            return String(localized: "report.sexualContent")

        case .spamScam:
            return String(localized: "report.spamScam")

        case .impersonation:
            return String(localized: "report.impersonation")

        case .other:
            return String(localized: "report.other")
        }
    }
}