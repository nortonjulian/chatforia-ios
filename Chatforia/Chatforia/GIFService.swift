import Foundation

struct GIFPickerItem: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let previewURL: URL?
    let fullURL: URL?
    let tenorID: String?
}

enum GIFServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case badURL

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing GIF API key."
        case .invalidResponse:
            return "Invalid GIF response."
        case .badURL:
            return "Invalid GIF URL."
        }
    }
}

final class GIFService {
    static let shared = GIFService()
    private init() {}

    // Replace with your real values or wire these through your config layer.
    private let apiKey = AppEnvironment.tenorAPIKey
    private let clientKey = "chatforia_ios"

    func featured(limit: Int = 24) async throws -> [GIFPickerItem] {
        let url = try makeURL(
            path: "/v2/featured",
            queryItems: [
                URLQueryItem(name: "key", value: validatedAPIKey()),
                URLQueryItem(name: "client_key", value: clientKey),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )

        let response: TenorResponse = try await fetch(url: url)
        return response.results.map(\.pickerItem)
    }

    func search(query: String, limit: Int = 24) async throws -> [GIFPickerItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await featured(limit: limit)
        }

        let url = try makeURL(
            path: "/v2/search",
            queryItems: [
                URLQueryItem(name: "key", value: validatedAPIKey()),
                URLQueryItem(name: "client_key", value: clientKey),
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )

        let response: TenorResponse = try await fetch(url: url)
        return response.results.map(\.pickerItem)
    }

    func registerShare(item: GIFPickerItem, query: String?) async {
        guard let apiKey = try? validatedAPIKey(),
              let tenorID = item.tenorID,
              let url = try? makeURL(
                path: "/v2/registershare",
                queryItems: [
                    URLQueryItem(name: "key", value: apiKey),
                    URLQueryItem(name: "client_key", value: clientKey),
                    URLQueryItem(name: "id", value: tenorID),
                    URLQueryItem(name: "q", value: query?.trimmingCharacters(in: .whitespacesAndNewlines))
                ]
              ) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Non-blocking analytics-style call; safe to ignore for UX.
        }
    }

    private func validatedAPIKey() throws -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GIFServiceError.missingAPIKey }
        return trimmed
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "tenor.googleapis.com"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw GIFServiceError.badURL
        }
        return url
    }

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw GIFServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Tenor DTOs

private struct TenorResponse: Decodable {
    let results: [TenorResult]
}

private struct TenorResult: Decodable {
    let id: String
    let title: String?
    let mediaFormats: TenorMediaFormats

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case mediaFormats = "media_formats"
    }

    var pickerItem: GIFPickerItem {
        let preview = mediaFormats.tinygif?.url ?? mediaFormats.nanogif?.url ?? mediaFormats.gif?.url
        let full = mediaFormats.gif?.url ?? mediaFormats.mediumgif?.url ?? mediaFormats.tinygif?.url

        return GIFPickerItem(
            id: id,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "GIF",
            previewURL: preview.flatMap(URL.init(string:)),
            fullURL: full.flatMap(URL.init(string:)),
            tenorID: id
        )
    }
}

private struct TenorMediaFormats: Decodable {
    let gif: TenorMediaObject?
    let mediumgif: TenorMediaObject?
    let tinygif: TenorMediaObject?
    let nanogif: TenorMediaObject?
}

private struct TenorMediaObject: Decodable {
    let url: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
