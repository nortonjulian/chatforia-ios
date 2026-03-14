import Foundation

struct UserDTO: Codable, Identifiable {
    let id: Int
    let email: String?
    let username: String
    let publicKey: String?
    let plan: String?
    let role: String?
    let preferredLanguage: String?
    let theme: String?
    let avatarUrl: String?
}
