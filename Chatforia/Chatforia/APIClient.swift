//
//  APIClient.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//  Updated by ChatGPT on 2026-02-15.
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
    case decoding(Error)           // carries underlying decoding error
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .unauthorized: return "Not authorized."
        case .server(let status, let message): return "Server error (\(status)): \(message ?? "Unknown")"
        case .decoding(let err): return "Failed to decode response: \(err.localizedDescription)"
        case .network(let err): return err.localizedDescription
        }
    }
}

// MARK: - APIClient

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

    /// Send a typed API request and decode the response into `T`.
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

            // Quick guard for empty responses (some endpoints may legitimately be empty)
            if data.isEmpty {
                let emptyJSON = "{}".data(using: .utf8) ?? Data()
                do {
                    let decoder = JSONDecoder.tolerantISO8601Decoder()
                    return try decoder.decode(T.self, from: emptyJSON)
                } catch {
                    throw APIError.decoding(NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty response body"]))
                }
            }

            // Decode using tolerant ISO8601 decoder and log helpful details on failure
            do {
                let decoder = JSONDecoder.tolerantISO8601Decoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                // Helpful logging for debugging decoding issues
                print("❗️JSON Decode failed for \(request.path):", error)

                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .dataCorrupted(let ctx):
                        print("dataCorrupted:", ctx.debugDescription)
                    case .keyNotFound(let key, let ctx):
                        print("keyNotFound:", key.stringValue, ctx.debugDescription)
                    case .typeMismatch(let type, let ctx):
                        print("typeMismatch:", String(describing: type), ctx.debugDescription)
                    case .valueNotFound(let type, let ctx):
                        print("valueNotFound:", String(describing: type), ctx.debugDescription)
                    @unknown default:
                        print("unknown DecodingError")
                    }
                }

                if let s = String(data: data, encoding: .utf8) {
                    print("---- RAW JSON PREVIEW (truncated to 4000 chars) ----")
                    print(s.prefix(4000))
                } else {
                    print("---- RAW RESPONSE IS NON-UTF8 (\(data.count) bytes) ----")
                }

                throw APIError.decoding(error)
            }

        } catch let apiError as APIError {
            // Don't re-wrap APIError
            throw apiError
        } catch {
            throw APIError.network(error)
        }
    }
    
    func sendRaw(_ request: APIRequest, token: String?) async throws -> (Data, HTTPURLResponse) {
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

            if http.statusCode == 401 {
                throw APIError.unauthorized
            }

            // Let caller decide how to handle non-2xx (or throw here to keep parity with send)
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? nil
                throw APIError.server(status: http.statusCode, message: msg)
            }

            return (data, http)
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.network(error)
        }
    }
}
