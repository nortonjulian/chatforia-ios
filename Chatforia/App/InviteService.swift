import Foundation

final class InviteService {
    static let shared = InviteService()
    private init() {}

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
            return "\(name) invited you to Chatforia — a better way to message globally. Join here: \(inviteURL)"
        }
        return "Join me on Chatforia — a better way to message globally. Join here: \(inviteURL)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
