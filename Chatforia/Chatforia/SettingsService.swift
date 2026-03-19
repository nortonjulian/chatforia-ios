import Foundation

final class SettingsService {
    static let shared = SettingsService()
    private init() {}

    func updateSettings(_ request: UserSettingsUpdateRequest, token: String) async throws -> UserDTO {
        let body = try JSONEncoder().encode(request)

        // Don’t decode PATCH response body at all.
        _ = try await APIClient.shared.sendRaw(
            APIRequest(
                path: "users/me",
                method: .PATCH,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        // Re-fetch canonical user after save.
        let response: MeResponse = try await APIClient.shared.send(
            APIRequest(
                path: "auth/me",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.user
    }
}
