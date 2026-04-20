import Foundation

struct ConversationDTO: Codable, Identifiable {
    let kind: String
    let id: Int
    let title: String
    let displayName: String?
    let updatedAt: String
    let isGroup: Bool?
    let phone: String?
    let unreadCount: Int?
    let avatarUsers: [ConversationAvatarUserDTO]?
    let last: ConversationLastDTO?

    var uniqueId: String {
        "\(kind)-\(id)"
    }
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
    var asChatRoomDTO: ChatRoomDTO {
        ChatRoomDTO(
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
