import Foundation

struct ChatRoomDTO: Codable, Identifiable {
    let id: Int
    let name: String?
    let isGroup: Bool?
    let updatedAt: String?
    let lastMessage: MessagePreviewDTO?
    let participants: [UserPreviewDTO]?
}

struct UserPreviewDTO: Codable, Identifiable {
    let id: Int
    let username: String?
}

struct MessagePreviewDTO: Codable, Identifiable {
    let id: Int
    let content: String?
    let createdAt: String?
    let sender: UserPreviewDTO?
}

