//
//  APIClient.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

enum HTTPMethod: String { case GET, POST }

struct APIRequest {
    let path: String
    let method: HTTPMethod
    let body: Data?
    let requiresAuth: Bool

    init(path: String, method: HTTPMethod, body: Data? = nil, requiresAuth: Bool = true) {
        self.path = path
        self.method = method
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case server(status: Int, message: String?)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .unauthorized: return "Not authorized."
        case .server(let status, let message): return "Server error (\(status)): \(message ?? "Unknown")"
        case .decoding: return "Failed to decode response."
        case .network(let err): return err.localizedDescription
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    /// Build a URL from AppEnvironment.apiBaseURL and the request.path while preserving any query string in `request.path`.
    /// This avoids percent-encoding the `?` and query portion when appending the path.
    private func buildURL(from request: APIRequest) throws -> URL {
        let pathAndQuery = request.path
        guard var baseComponents = URLComponents(url: AppEnvironment.apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        if pathAndQuery.contains("?") {
            let parts = pathAndQuery.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let pathPart = String(parts[0])
            let queryPart = parts.count > 1 ? String(parts[1]) : nil

            // Ensure path combines correctly with base path
            if baseComponents.path.hasSuffix("/") && pathPart.hasPrefix("/") {
                baseComponents.path += String(pathPart.dropFirst())
            } else {
                // strip excessive slashes and append
                let trimmed = pathPart.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                baseComponents.path += "/" + trimmed
            }

            // set percentEncodedQuery to avoid double-encoding the query string
            baseComponents.percentEncodedQuery = queryPart
        } else {
            // no query in path
            if baseComponents.path.hasSuffix("/") && pathAndQuery.hasPrefix("/") {
                baseComponents.path += String(pathAndQuery.dropFirst())
            } else {
                let trimmed = pathAndQuery.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                baseComponents.path += "/" + trimmed
            }
        }

        guard let url = baseComponents.url else {
            throw APIError.invalidURL
        }
        return url
    }

    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T {
        // build URL safely (preserve query)
        let url: URL
        do {
            url = try buildURL(from: request)
        } catch {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = request.method.rawValue
        req.timeoutInterval = AppEnvironment.requestTimeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = request.body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        if request.requiresAuth {
            guard let token else { throw APIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.server(status: -1, message: "Non-HTTP response")
            }

            print("📡 STATUS \(http.statusCode) for \(request.path)")
            print("📦 BYTES \(data.count)")
            print("🔎 RAW RESPONSE for \(request.path):")
            print(String(data: data, encoding: .utf8) ?? "<non-utf8 data>")

            // Handle auth + non-success statuses
            if http.statusCode == 401 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                if !msg.isEmpty { print("🚫 401 Unauthorized body:", msg) }
                throw APIError.unauthorized
            }

            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.server(status: http.statusCode, message: msg)
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding
            }

        } catch let apiError as APIError {
            // Don't re-wrap your own errors
            throw apiError
        } catch {
            throw APIError.network(error)
        }
    }
}
