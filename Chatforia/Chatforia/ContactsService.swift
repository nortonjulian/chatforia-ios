import Foundation

final class ContactsService {
    static let shared = ContactsService()
    private init() {}

    func fetchContacts(query: String? = nil, limit: Int = 50, cursor: Int? = nil, token: String) async throws -> ContactsResponseDTO {
        var parts: [String] = ["limit=\(limit)"]

        if let cursor {
            parts.append("cursor=\(cursor)")
        }

        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            parts.append("q=\(encoded)")
        }

        let path = "contacts" + (parts.isEmpty ? "" : "?\(parts.joined(separator: "&"))")

        return try await APIClient.shared.send(
            APIRequest(path: path, method: .GET, requiresAuth: true),
            token: token
        )
    }

    func saveUserContact(userId: Int, alias: String? = nil, favorite: Bool = false, token: String) async throws -> ContactDTO {
        struct Request: Encodable {
            let userId: Int
            let alias: String?
            let favorite: Bool
        }

        let body = try JSONEncoder().encode(
            Request(
                userId: userId,
                alias: alias?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                favorite: favorite
            )
        )

        return try await APIClient.shared.send(
            APIRequest(path: "contacts", method: .POST, body: body, requiresAuth: true),
            token: token
        )
    }

    func saveExternalContact(phone: String, externalName: String? = nil, alias: String? = nil, favorite: Bool = false, token: String) async throws -> ContactDTO {
        struct Request: Encodable {
            let externalPhone: String
            let externalName: String?
            let alias: String?
            let favorite: Bool
        }

        let body = try JSONEncoder().encode(
            Request(
                externalPhone: phone,
                externalName: externalName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                alias: alias?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                favorite: favorite
            )
        )

        return try await APIClient.shared.send(
            APIRequest(path: "contacts", method: .POST, body: body, requiresAuth: true),
            token: token
        )
    }

    func importExternalContacts(_ contacts: [PhoneContactDTO], token: String) async throws -> ImportedContactsResponseDTO {
        struct ImportItem: Encodable {
            let externalPhone: String
            let externalName: String?
            let alias: String?
            let favorite: Bool
        }

        struct Request: Encodable {
            let items: [ImportItem]
        }

        let items = contacts.map {
            ImportItem(
                externalPhone: $0.phoneNumber,
                externalName: $0.displayName,
                alias: nil,
                favorite: false
            )
        }

        let body = try JSONEncoder().encode(Request(items: items))

        return try await APIClient.shared.send(
            APIRequest(path: "contacts/import", method: .POST, body: body, requiresAuth: true),
            token: token
        )
    }

    func lookupUser(username: String, token: String) async throws -> UserLookupResponseDTO {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed

        return try await APIClient.shared.send(
            APIRequest(path: "users/lookup?username=\(encoded)", method: .GET, requiresAuth: true),
            token: token
        )
    }

    func findExistingUserContact(userId: Int, token: String) async throws -> ContactDTO? {
        let response = try await fetchContacts(token: token)
        return response.items.first { ($0.user?.id ?? $0.userId) == userId }
    }
}

struct UserLookupResponseDTO: Decodable {
    let userId: Int
    let username: String
}

struct ImportedContactsResponseDTO: Decodable {
    let ok: Bool
    let importedCount: Int
    let items: [ContactDTO]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
