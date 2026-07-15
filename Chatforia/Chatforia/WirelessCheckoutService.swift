import Foundation

private struct WirelessCheckoutRequest: Encodable {
    let product: String
    let platform: String
}

private struct WirelessCheckoutResponse: Decodable {
    let url: String?
    let checkoutUrl: String?
    let sessionId: String?
    let plan: String?

    var resolvedURL: URL? {
        if let checkoutUrl,
           !checkoutUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(string: checkoutUrl)
        }

        if let url,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(string: url)
        }

        return nil
    }
}

private enum WirelessCheckoutError: LocalizedError {
    case missingCheckoutURL

    var errorDescription: String? {
        switch self {
        case .missingCheckoutURL:
            return "The server did not return a checkout URL."
        }
    }
}

final class WirelessCheckoutService {
    static let shared = WirelessCheckoutService()

    private init() {}

    func createCheckout(
        product: String
    ) async throws -> URL {
        guard let token = TokenStore.shared.read() else {
            throw APIError.unauthorized
        }

        let body = try JSONEncoder().encode(
            WirelessCheckoutRequest(
                product: product,
                platform: "ios"
            )
        )

        let response: WirelessCheckoutResponse =
            try await APIClient.shared.send(
                APIRequest(
                    path: "billing/checkout",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )

        guard let checkoutURL = response.resolvedURL else {
            throw WirelessCheckoutError.missingCheckoutURL
        }

        return checkoutURL
    }
} 
