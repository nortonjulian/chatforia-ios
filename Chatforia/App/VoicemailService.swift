import Foundation

final class VoicemailService {
    static let shared = VoicemailService()
    private init() {}

    func fetchVoicemails(token: String) async throws -> [VoicemailDTO] {
        let response: VoicemailListResponseDTO = try await APIClient.shared.send(
            APIRequest(
                path: "voicemail",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.voicemails
    }

    func setVoicemailRead(
        id: String,
        isRead: Bool,
        token: String
    ) async throws {
        struct Body: Encodable {
            let isRead: Bool
        }

        let body = try JSONEncoder().encode(Body(isRead: isRead))

        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "voicemail/\(id)/read",
                method: .PATCH,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func deleteVoicemail(
        id: String,
        token: String
    ) async throws {
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "voicemail/\(id)",
                method: .DELETE,
                requiresAuth: true
            ),
            token: token
        )
    }
}
