import Foundation

struct SMSThreadDTO: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let createdAt: Date?
    let updatedAt: Date?
    let archivedAt: Date?
    let contactPhone: String?
    let displayName: String?
    let contactName: String?
    let participants: [SMSParticipantDTO]
    let messages: [SMSMessageDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case createdAt
        case updatedAt
        case archivedAt
        case contactPhone
        case displayName
        case contactName
        case participants
        case messages
    }

    var resolvedTitle: String {
        let preferred =
            displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? contactName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

        return preferred ?? "SMS #\(id)"
    }

    var sortedMessages: [SMSMessageDTO] {
        messages.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }
}

struct SMSParticipantDTO: Decodable, Identifiable {
    let rawId: Int?
    let phone: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case phone
        case createdAt
    }

    var id: String {
        if let rawId { return "participant-\(rawId)" }
        if let phone, !phone.isEmpty { return "participant-\(phone)" }
        return "participant-unknown"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
