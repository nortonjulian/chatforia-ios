import Foundation

final class WirelessService {
    static let shared = WirelessService()
    private init() {}

    func fetchWirelessStatus() async throws -> WirelessStatusDTO {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        return try await APIClient.shared.send(
            APIRequest(
                path: "api/wireless/status",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
    }
}
