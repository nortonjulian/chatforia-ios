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
        let name = inviterUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return String(
                format: appText(
                    "invite.shareMessageWithName",
                    languageCode: appLanguage
                ),
                name,
                inviteURL
            )
        }

        return String(
            format: String(
                format: appText(
                    "invite.shareMessageGeneric",
                    languageCode: appLanguage
                ),
                inviteURL
            ),
            inviteURL
        )
            }
        }

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
