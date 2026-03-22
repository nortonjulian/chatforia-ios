import Foundation

struct ContactDTO: Codable, Identifiable, Equatable {
    let id: Int
    let alias: String?
    let favorite: Bool?
    let externalPhone: String?
    let externalName: String?
    let createdAt: Date?
    let userId: Int?
    let user: ContactUserDTO?
}

struct ContactUserDTO: Codable, Identifiable, Equatable {
    let id: Int
    let username: String?
    let avatarUrl: String?
}

struct ContactsResponseDTO: Decodable {
    let items: [ContactDTO]
    let nextCursor: Int?
    let count: Int?
}
