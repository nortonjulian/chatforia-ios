import Foundation

final class InviteService {
    static let shared = InviteService()
    private init() {}
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    func createInvite(
        targetPhone: String? = nil,
        targetEmail: String? = nil,
        channel: String = "share_link",
        token: String
    ) async throws -> CreatePeopleInviteResponseDTO {
        struct Request: Encodable {
            let targetPhone: String?
            let targetEmail: String?
            let channel: String
        }

        let normalizedPhone = targetPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedEmail = targetEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty

        let body = try JSONEncoder().encode(
            Request(
                targetPhone: normalizedPhone,
                targetEmail: normalizedEmail,
                channel: channel
            )
        )

        return try await APIClient.shared.send(
            APIRequest(
                path: "people-invites",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func previewInvite(code: String) async throws -> PreviewPeopleInviteResponseDTO {
        try await APIClient.shared.send(
            APIRequest(
                path: "people-invites/\(code)",
                method: .GET,
                requiresAuth: false
            ),
            token: nil
        )
    }

    func redeemInvite(code: String, token: String) async throws -> RedeemPeopleInviteResponseDTO {
        try await APIClient.shared.send(
            APIRequest(
                path: "people-invites/\(code)/redeem",
                method: .POST,
                requiresAuth: true
            ),
            token: token
        )
    }

    func createShareMessage(
        inviterUsername: String?,
        inviteURL: String
    ) -> String {
        let name = inviterUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let name, !name.isEmpty {
            let template = appText(
                "invite.shareMessageWithName",
                languageCode: appLanguage
            )

            // Current translations use two {value} placeholders:
            // first = inviter name, second = invitation URL.
            if template.contains("{value}") {
                return template
                    .replacingFirstOccurrence(of: "{value}", with: name)
                    .replacingFirstOccurrence(of: "{value}", with: inviteURL)
            }

            // Supports standard %@ localization placeholders as a fallback.
            return String(
                format: template,
                name,
                inviteURL
            )
        }

        let template = appText(
            "invite.shareMessageGeneric",
            languageCode: appLanguage
        )

        if template.contains("{value}") {
            return template.replacingOccurrences(
                of: "{value}",
                with: inviteURL
            )
        }

        return String(
            format: template,
            inviteURL
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func replacingFirstOccurrence(
        of target: String,
        with replacement: String
    ) -> String {
        guard let range = range(of: target) else {
            return self
        }

        return replacingCharacters(
            in: range,
            with: replacement
        )
    }
}
