import Foundation

final class SettingsService {
    static let shared = SettingsService()
    private init() {}
    
    struct AccessibilitySettingsUpdateRequest: Encodable {
        let a11yUiFont: String?
        let a11yVisualAlerts: Bool?
        let a11yVibrate: Bool?
        let a11yFlashOnCall: Bool?
        let a11yLiveCaptions: Bool?
        let a11yVoiceNoteSTT: Bool?
        let a11yCaptionFont: String?
        let a11yCaptionBg: String?
    }

    private struct UserEnvelopeResponse: Decodable {
        let user: UserDTO?
    }

    private struct ThemeUpdateRequest: Encodable {
        let theme: String
    }
    
    func deleteAccount(token: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "users/me",
                method: .DELETE,
                requiresAuth: true
            ),
            token: token
        )
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
    
    func updateAccessibility(_ request: AccessibilitySettingsUpdateRequest, token: String) async throws -> UserDTO {
        let body = try JSONEncoder().encode(request)

        let response: UserEnvelopeResponse = try await APIClient.shared.send(
            APIRequest(
                path: "users/me/a11y",
                method: .PATCH,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        if let user = response.user {
            return user
        }

        let me: MeResponse = try await APIClient.shared.send(
            APIRequest(
                path: "auth/me",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return me.user
    }
}
