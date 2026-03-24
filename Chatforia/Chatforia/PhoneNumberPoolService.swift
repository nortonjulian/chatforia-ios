import Foundation

struct MyAssignedNumberDTO: Decodable {
    let number: AssignedNumberDTO?
}

struct AssignedNumberDTO: Decodable, Identifiable {
    var id: String { e164 }
    let e164: String
    let status: String?
    let capabilities: [String]?
    let keepLocked: Bool?
    let releaseAfter: String?
}

struct NumberPoolResponseDTO: Decodable {
    let numbers: [AvailableNumberDTO]?
    let error: String?
    let message: String?
}

struct AvailableNumberDTO: Decodable, Identifiable {
    var id: String { e164 ?? number ?? UUID().uuidString }
    let e164: String?
    let number: String?
    let locality: String?
    let local: String?
    let display: String?
    let capabilities: [String]?
}

struct LeaseNumberResponseDTO: Decodable {
    let ok: Bool?
    let number: AssignedNumberDTO?
    let error: String?
}

final class PhoneNumberPoolService {
    static let shared = PhoneNumberPoolService()
    private init() {}

    func fetchMyNumber(token: String?) async throws -> MyAssignedNumberDTO {
        try await APIClient.shared.send(
            APIRequest(path: "numbers/my", method: .GET, requiresAuth: true),
            token: token
        )
    }

    func searchPool(
        country: String = "US",
        capability: String = "voice",
        areaCode: String? = nil,
        limit: Int = 15,
        forSale: Bool = false,
        token: String?
    ) async throws -> NumberPoolResponseDTO {
        var parts: [String] = [
            "country=\(country)",
            "capability=\(capability)",
            "limit=\(limit)",
            "forSale=\(forSale ? "true" : "false")"
        ]

        if let areaCode, !areaCode.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            parts.append("areaCode=\(areaCode)")
        }

        let path = "numbers/pool?\(parts.joined(separator: "&"))"

        return try await APIClient.shared.send(
            APIRequest(path: path, method: .GET, requiresAuth: true),
            token: token
        )
    }
    
    func leaseNumber(e164: String, token: String?) async throws -> LeaseNumberResponseDTO {
        struct Body: Encodable {
            let e164: String
        }

        let body = try JSONEncoder().encode(Body(e164: e164))

        return try await APIClient.shared.send(
            APIRequest(path: "numbers/lease", method: .POST, body: body, requiresAuth: true),
            token: token
        )
    }
}
