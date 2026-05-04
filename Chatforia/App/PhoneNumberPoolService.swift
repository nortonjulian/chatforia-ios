import Foundation

struct MyAssignedNumberDTO: Decodable {
    let number: AssignedNumberDTO?
}

struct AssignedNumberDTO: Decodable, Identifiable {
    var id: String { e164 }
    let e164: String
    let status: String?
    let capabilities: CapabilityList?
    let keepLocked: Bool?
    let releaseAfter: String?
    let holdUntil: String?
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
    let region: String?
    let display: String?
    let capabilities: CapabilityList?
}

struct LeaseNumberResponseDTO: Decodable {
    let ok: Bool?
    let number: AssignedNumberDTO?
    let error: String?
}

struct CapabilityList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let arr = try? container.decode([String].self) {
            values = arr.map { $0.lowercased() }
            return
        }

        if let dict = try? container.decode([String: Bool].self) {
            values = dict
                .filter { $0.value }
                .map { $0.key.lowercased() }
                .sorted()
            return
        }

        values = []
    }
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
        limit: Int = 25,
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
    
    func leaseNumber(e164: String, purchaseIntent: Bool = false, token: String?) async throws -> LeaseNumberResponseDTO {
        struct Body: Encodable {
            let e164: String
            let purchaseIntent: Bool?
        }

        let body = try JSONEncoder().encode(
            Body(e164: e164, purchaseIntent: purchaseIntent ? true : nil)
        )

        return try await APIClient.shared.send(
            APIRequest(path: "numbers/lease", method: .POST, body: body, requiresAuth: true),
            token: token
        )
    }
}
