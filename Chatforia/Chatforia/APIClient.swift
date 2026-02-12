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
    case unauthorized
    case server(status: Int, message: String?)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
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

    func send<T: Decodable>(_ request: APIRequest, token: String?) async throws -> T {
        let url = Environment.apiBaseURL.appendingPathComponent(request.path)

        var req = URLRequest(url: url)
        req.httpMethod = request.method.rawValue
        req.timeoutInterval = Environment.requestTimeout
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
                let msg = String(data: data, encoding: .utf8)
                throw APIError.unauthorized  // or: .server(status: 401, message: msg)
            }

            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8)
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

