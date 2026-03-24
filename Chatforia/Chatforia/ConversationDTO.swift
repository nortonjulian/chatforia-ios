import Foundation

struct ConversationDTO: Codable, Identifiable {
    let kind: String
    let id: Int
    let title: String
    let updatedAt: String
    let isGroup: Bool?
    let phone: String?
    let unreadCount: Int?
    let last: ConversationLastDTO?

    var uniqueId: String {
        "\(kind)-\(id)"
    }
}

struct ConversationLastDTO: Codable {
    let text: String?
    let messageId: Int?
    let at: String?
    let hasMedia: Bool?
    let mediaCount: Int?
    let mediaKinds: [String]?
    let thumbUrl: String?
}

extension ConversationDTO {
    var asChatRoomDTO: ChatRoomDTO {
        ChatRoomDTO(
            id: id,
            name: title,
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
            participants: nil
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
