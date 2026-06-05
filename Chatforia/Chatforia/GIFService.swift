import Foundation

struct GIFPickerItem: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let title: String
    let previewURL: URL?
    let fullURL: URL?
    let tenorID: String?
}

enum GIFServiceError: LocalizedError {
    case invalidResponse
    case badURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid GIF response."
        case .badURL:
            return "Invalid GIF URL."
        }
    }
}

@MainActor
final class GIFService {
    static let shared = GIFService()
    private init() {}

    func featured(limit: Int = 24) async throws -> [GIFPickerItem] {
        try await search(query: "trending", limit: limit)
    }

    func search(query: String, limit: Int = 24) async throws -> [GIFPickerItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "trending"
            : query.trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents(
            url: AppEnvironment.apiBaseURL.appendingPathComponent("stickers/search"),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        guard let url = components?.url else {
            throw GIFServiceError.badURL
        }

        let response: BackendGIFResponse = try await fetch(url: url)
        return response.results.map { $0.pickerItem }
    }

    func registerShare(item: GIFPickerItem, query: String?) async {
        // Backend handles Tenor access. No client-side registershare needed.
    }

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = TokenStore.shared.read(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw GIFServiceError.invalidResponse
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct BackendGIFResponse: Decodable {
    let results: [BackendGIFItem]
}

private struct BackendGIFItem: Decodable {
    let id: String?
    let title: String?
    let url: String?
    let previewUrl: String?
    let previewURL: String?
    let tenorID: String?
    let tenorId: String?

    var pickerItem: GIFPickerItem {
        let resolvedId = id ?? tenorID ?? tenorId ?? url ?? UUID().uuidString
        let preview = previewUrl ?? previewURL ?? url

        return GIFPickerItem(
            id: resolvedId,
            title: title?.nilIfBlank ?? "GIF",
            previewURL: preview.flatMap(URL.init(string:)),
            fullURL: url.flatMap(URL.init(string:)),
            tenorID: tenorID ?? tenorId ?? id
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
