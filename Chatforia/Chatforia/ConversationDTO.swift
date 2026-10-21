import Foundation

struct ConversationDTO: Codable, Identifiable {
    let kind: String
    let id: Int?
    let title: String
    let displayName: String?
    let updatedAt: String?
    let isGroup: Bool?
    let phone: String?
    let unreadCount: Int?
    let avatarUsers: [ConversationAvatarUserDTO]?
    let last: ConversationLastDTO?

    var isRandomChat: Bool? = nil
    var randomChat: RandomChatConversationDTO? = nil
    var randomChatRoomId: Int? = nil

    var uniqueId: String {
        if let id {
            return "\(kind)-\(id)"
        }
        return "\(kind)-draft-\(phone ?? title)"
    }
}

struct RandomChatConversationDTO: Codable {
    let id: Int?
    let chatRoomId: Int
    let myAlias: String?
    let partnerAlias: String?
    let isUnlocked: Bool?
    let endedAt: String?
    let endedReason: String?
    let endedById: Int?
}

struct ConversationAvatarUserDTO: Codable, Identifiable, Hashable {
    let id: Int
    let username: String?
    let displayName: String?
    let avatarUrl: String?
}

struct ConversationLastDTO: Codable {
    let text: String?
    let messageId: Int?
    let at: String?
    let hasMedia: Bool?
    let mediaCount: Int?
    let mediaKinds: [String]?
    let thumbUrl: String?
    let senderName: String?
}

extension ConversationDTO {
    var asChatRoomDTO: ChatRoomDTO? {
        guard let id else { return nil }

        return ChatRoomDTO(
            id: id,
            name: displayName ?? title,
            isGroup: isGroup,
            updatedAt: updatedAt,
            phone: phone,
            lastMessage: {
                guard let last else { return nil }
                return MessagePreviewDTO(
                    id: last.messageId ?? 0,
                    content: last.text,
                    createdAt: last.at,
                    sender: nil
                )
            }(),
            participants: avatarUsers?.map {
                UserPreviewDTO(
                    id: $0.id,
                    username: $0.displayName ?? $0.username
                )
            }
        )
    }
}

struct ChatRoomDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let isGroup: Bool?
    let updatedAt: String?
    let phone: String?
    let lastMessage: MessagePreviewDTO?
    let participants: [UserPreviewDTO]?
}

struct UserPreviewDTO: Codable, Identifiable, Hashable {
    let id: Int
    let username: String?
}

struct MessagePreviewDTO: Codable, Identifiable, Hashable {
    let id: Int
    let content: String?
    let createdAt: String?
    let sender: UserPreviewDTO?
}

// Shared by Chats search and New Chat. Display names are search terms, never
// identity keys: SMS identity is the normalized number; app identity is user ID.
enum ConversationLookup {
    static func phoneDigits(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "+()-.").union(.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({
            (48...57).contains(Int($0.value)) || allowed.contains($0)
        }), trimmed.filter({ $0 == "+" }).count <= 1,
        !trimmed.contains("+") || trimmed.hasPrefix("+") else { return nil }
        return trimmed.filter { "0123456789".contains($0) }
    }

    static func normalizePhone(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var digits = phoneDigits(trimmed) else { return nil }
        let international = trimmed.hasPrefix("+") || digits.hasPrefix("00")
        if !trimmed.hasPrefix("+"), digits.hasPrefix("00") { digits.removeFirst(2) }
        guard (7...15).contains(digits.count), !digits.hasPrefix("0") else { return nil }
        if !international, digits.count == 10 { digits = "1" + digits }
        return "+" + digits
    }

    static func matches(_ item: ConversationDTO, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let names = (item.avatarUsers ?? []).flatMap { [$0.username, $0.displayName] }
        let fields = [item.title, item.displayName, item.phone, item.last?.text] + names
        if fields.compactMap({ $0 }).contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return true
        }
        guard let phone = item.phone,
              let queryDigits = phoneDigits(query), queryDigits.count >= 3,
              let storedDigits = phoneDigits(phone) else { return false }
        if let normalized = normalizePhone(query), normalized == normalizePhone(phone) { return true }
        return storedDigits.contains(queryDigits)
    }

}
