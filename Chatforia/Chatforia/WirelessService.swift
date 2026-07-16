import Foundation

struct ESIMCheckoutPurchaseDTO: Decodable, Equatable {
    let id: Int
    let addonKind: String
    let totalDataMb: Int
    let remainingDataMb: Int
    let expiresAt: Date?
}

struct ESIMCheckoutStatusDTO: Decodable, Equatable {
    let status: String
    let complete: Bool
    let paid: Bool
    let provisioned: Bool
    let sessionId: String
    let paymentStatus: String?
    let sessionStatus: String?
    let purchase: ESIMCheckoutPurchaseDTO?
}

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

    func fetchCheckoutStatus(
        sessionId: String
    ) async throws -> ESIMCheckoutStatusDTO {
        guard let token = TokenStore.shared.read(),
              !token.isEmpty else {
            throw APIError.unauthorized
        }

        let trimmedSessionId =
            sessionId.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedSessionId.isEmpty else {
            throw APIError.invalidURL
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(
                name: "session_id",
                value: trimmedSessionId
            ),
        ]

        guard let query =
                components.percentEncodedQuery else {
            throw APIError.invalidURL
        }

        return try await APIClient.shared.send(
            APIRequest(
                path:
                    "billing/checkout-status?\(query)",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
    }

}
