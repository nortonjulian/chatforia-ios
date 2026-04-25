import Foundation

final class SettingsService {
    static let shared = SettingsService()
    private init() {}

    private struct ThemeUpdateRequest: Encodable {
        let theme: String
    }

    func updateSettings(_ request: UserSettingsUpdateRequest, token: String) async throws -> UserDTO {
        let body = try JSONEncoder().encode(request)

        _ = try await APIClient.shared.sendRaw(
            APIRequest(
                path: "users/me",
                method: .PATCH,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

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

    func updateTheme(_ theme: String, token: String) async throws -> UserDTO {
        let body = try JSONEncoder().encode(ThemeUpdateRequest(theme: theme))

        _ = try await APIClient.shared.sendRaw(
            APIRequest(
                path: "users/me",
                method: .PATCH,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

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
