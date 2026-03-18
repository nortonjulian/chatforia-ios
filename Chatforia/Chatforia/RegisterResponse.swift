import Foundation

struct RegistrationResponseDTO: Decodable {
    let message: String?
    let token: String?
    let user: UserDTO?
    let privateKey: String?

    // Optional fallback fields if backend ever returns top-level user-ish data
    let id: Int?
    let username: String?
    let email: String?
    let publicKey: String?
    let plan: String?
    let role: String?
    let preferredLanguage: String?
    let theme: String?
    let avatarUrl: String?

    var resolvedUser: UserDTO? {
        if let user { return user }

        if let id, let username {
            return UserDTO(
                id: id,
                email: email,
                username: username,
                publicKey: publicKey,
                plan: plan,
                role: role,
                preferredLanguage: preferredLanguage,
                theme: theme,
                avatarUrl: avatarUrl
            )
        }

        return nil
    }
}
