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

struct ESIMReplacementInstallationDTO: Decodable, Equatable {
    let subscriberId: Int
    let iccid: String?
    let providerProfileId: String?
    let smdp: String?
    let activationCode: String?
    let lpaUri: String?
    let qrPayload: String?
}

struct ESIMReplacementDTO: Decodable, Equatable {
    let id: String
    let purchaseId: Int
    let status: String
    let oldIccid: String
    let newIccid: String?
    let remainingDataMb: Int
    let expiresAt: Date?
    let createdAt: Date?
    let completedAt: Date?
    let installation: ESIMReplacementInstallationDTO?
}

struct ESIMReplacementResponseDTO: Decodable, Equatable {
    let ok: Bool
    let replacement: ESIMReplacementDTO
}

final class WirelessService {
    static let shared = WirelessService()
    private let apiClient: APIClientSending
    private let tokenProvider: () -> String?

    init(
        apiClient: APIClientSending = APIClient.shared,
        tokenProvider: @escaping () -> String? = { TokenStore.shared.read() }
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func fetchWirelessStatus() async throws -> WirelessStatusDTO {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        return try await apiClient.send(
            APIRequest(
                path: "api/wireless/status",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
    }

    func replaceEsim(
        purchaseId: Int,
        idempotencyKey: String
    ) async throws -> ESIMReplacementResponseDTO {
        guard let token = tokenProvider(),
              !token.isEmpty else {
            throw APIError.unauthorized
        }

        guard purchaseId > 0 else {
            throw APIError.invalidURL
        }

        let key =
            idempotencyKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !key.isEmpty, key.count <= 200 else {
            throw APIError.invalidURL
        }

        return try await apiClient.send(
            APIRequest(
                path: "api/wireless/esim/\(purchaseId)/replace",
                method: .POST,
                requiresAuth: true,
                headers: [
                    "Idempotency-Key": key
                ]
            ),
            token: token
        )
    }

    func fetchCheckoutStatus(
        sessionId: String
    ) async throws -> ESIMCheckoutStatusDTO {
        guard let token = tokenProvider(),
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

        return try await apiClient.send(
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
