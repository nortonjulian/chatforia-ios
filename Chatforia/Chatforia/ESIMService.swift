import Foundation

final class ESIMService {
    static let shared = ESIMService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Change this if you want to source it from AppEnvironment later.
    /// Must point to the API host, not the web app host.
    private let baseURL = AppEnvironment.apiBaseURL

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func purchaseAndProvision(pack: DataPackOption) async throws -> ESIMActivationDTO {
        // Right now your backend reserves via /esim/profiles with a region.
        // You can later connect pack -> region/plan selection more deeply.
        let region = inferredRegion(from: pack)

        let requestBody = ReserveESIMRequest(region: region)
        let response: ReserveESIMResponse = try await send(
            path: "/esim/profiles",
            method: "POST",
            body: requestBody
        )

        return mapReserveResponseToDTO(response, fallbackPlanName: pack.title)
    }

    func fetchCurrentActivation() async throws -> ESIMActivationDTO? {
        let response: CurrentESIMResponse = try await send(
            path: "/esim/me",
            method: "GET",
            body: Optional<String>.none
        )

        guard let subscriber = response.subscriber else {
            return nil
        }

        return mapSubscriberToDTO(subscriber)
    }
}

// MARK: - Networking

private extension ESIMService {
    func send<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw ESIMServiceError.server(
                statusCode: 401,
                message: "Missing auth token"
            )
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔥 AUTH TOKEN:", token)
        
        print("🔥 HEADERS:", request.allHTTPHeaderFields ?? [:])

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // If your backend relies on cookie auth, shared URLSession will use the shared cookie store.
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ESIMServiceError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let apiError = try? decoder.decode(APIErrorResponse.self, from: data)
            throw ESIMServiceError.server(
                statusCode: http.statusCode,
                message: apiError?.message ?? apiError?.error ?? "Unknown server error"
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ESIMServiceError.decoding(error)
        }
    }
}

// MARK: - Mapping

private extension ESIMService {
    func mapReserveResponseToDTO(_ response: ReserveESIMResponse, fallbackPlanName: String?) -> ESIMActivationDTO {
        ESIMActivationDTO(
            smdpAddress: response.smdp,
            activationCode: response.activationCode,
            iccid: response.iccid,
            confirmationCode: nil,
            planName: fallbackPlanName,
            status: "ready_to_install",
            qrCodeURL: response.qrPayload ?? response.lpaUri,
            lpaUri: response.lpaUri ?? response.qrPayload ?? buildLPAUri(smdp: response.smdp, activationCode: response.activationCode)
        )
    }

    func mapSubscriberToDTO(_ subscriber: SubscriberResponse) -> ESIMActivationDTO {
        ESIMActivationDTO(
            smdpAddress: subscriber.smdp,
            activationCode: subscriber.activationCode,
            iccid: subscriber.iccid,
            confirmationCode: nil,
            planName: nil,
            status: subscriber.status ?? "ready_to_install",
            qrCodeURL: subscriber.qrPayload ?? subscriber.lpaUri,
            lpaUri: subscriber.lpaUri ?? subscriber.qrPayload ?? buildLPAUri(smdp: subscriber.smdp, activationCode: subscriber.activationCode)
        )
    }

    func buildLPAUri(smdp: String?, activationCode: String?) -> String? {
        guard
            let smdp = smdp?.trimmingCharacters(in: .whitespacesAndNewlines),
            !smdp.isEmpty,
            let activationCode = activationCode?.trimmingCharacters(in: .whitespacesAndNewlines),
            !activationCode.isEmpty
        else {
            return nil
        }

        // Standard fallback shape your web flow is already using.
        return "LPA:1$\(smdp)$\(activationCode)"
    }

    func inferredRegion(from pack: DataPackOption) -> String {
        let lower = pack.product.lowercased()

        if lower.contains("eu") || lower.contains("europe") {
            return "EU"
        }
        if lower.contains("uk") {
            return "UK"
        }
        if lower.contains("ca") || lower.contains("canada") {
            return "CA"
        }
        if lower.contains("au") || lower.contains("australia") {
            return "AU"
        }
        if lower.contains("jp") || lower.contains("japan") {
            return "JP"
        }

        return "US"
    }
}

// MARK: - DTOs for backend responses

private struct ReserveESIMRequest: Encodable {
    let region: String
}

private struct ReserveESIMResponse: Decodable {
    let providerProfileId: String?
    let iccid: String?
    let iccidHint: String?
    let smdp: String?
    let activationCode: String?
    let lpaUri: String?
    let qrPayload: String?
    let region: String?
}

private struct CurrentESIMResponse: Decodable {
    let subscriber: SubscriberResponse?
}

private struct SubscriberResponse: Decodable {
    let id: Int?
    let provider: String?
    let providerProfileId: String?
    let iccid: String?
    let iccidHint: String?
    let smdp: String?
    let activationCode: String?
    let lpaUri: String?
    let qrPayload: String?
    let msisdn: String?
    let region: String?
    let status: String?
}

private struct APIErrorResponse: Decodable {
    let error: String?
    let message: String?
}

// MARK: - Errors

enum ESIMServiceError: LocalizedError {
    case invalidResponse
    case decoding(Error)
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .decoding(let error):
            return "Failed to read eSIM data: \(error.localizedDescription)"
        case .server(_, let message):
            return message
        }
    }
}
