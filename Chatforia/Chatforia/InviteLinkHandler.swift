import Foundation

enum InviteLinkHandler {
    static func extractPeopleInviteCode(from url: URL) -> String? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if let index = pathComponents.firstIndex(of: "i"),
           pathComponents.indices.contains(index + 1) {
            let code = pathComponents[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            return code.isEmpty ? nil : code
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "invite" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            return code
        }

        return nil
    }
}
