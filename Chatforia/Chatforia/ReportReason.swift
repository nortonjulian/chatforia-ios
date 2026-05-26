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

    func title(languageCode: String) -> String {
        switch self {

        case .harassment:
            return appText(
                "report.harassment",
                languageCode: languageCode
            )

        case .threats:
            return appText(
                "report.threats",
                languageCode: languageCode
            )

        case .hate:
            return appText(
                "report.hate",
                languageCode: languageCode
            )

        case .sexualContent:
            return appText(
                "report.sexualContent",
                languageCode: languageCode
            )

        case .spamScam:
            return appText(
                "report.spamScam",
                languageCode: languageCode
            )

        case .impersonation:
            return appText(
                "report.impersonation",
                languageCode: languageCode
            )

        case .other:
            return appText(
                "report.other",
                languageCode: languageCode
            )
        }
    }
}
