import Foundation

struct RiaChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
