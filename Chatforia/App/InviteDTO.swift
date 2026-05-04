import Foundation

struct PeopleInviteDTO: Codable, Equatable, Identifiable {
    let inviteId: Int?
    let code: String
    let inviterUserId: Int?
    let targetPhone: String?
    let targetEmail: String?
    let channel: String?
    let status: String
    let acceptedByUserId: Int?
    let createdAt: String?
    let updatedAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case inviteId = "id"
        case code
        case inviterUserId
        case targetPhone
        case targetEmail
        case channel
        case status
        case acceptedByUserId
        case createdAt
        case updatedAt
        case expiresAt
    }

    var id: String { code }
}

struct PeopleInvitePreviewDTO: Codable, Equatable {
    let code: String
    let status: String
    let targetPhone: String?
    let targetEmail: String?
    let inviterUser: InviteUserDTO?
    let expiresAt: String?
}

struct InviteUserDTO: Codable, Equatable, Identifiable {
    let id: Int
    let username: String?
    let avatarUrl: String?
}

struct CreatePeopleInviteResponseDTO: Decodable {
    let ok: Bool
    let invite: PeopleInviteDTO
    let url: String
}

struct PreviewPeopleInviteResponseDTO: Decodable {
    let ok: Bool
    let invite: PeopleInvitePreviewDTO
}

struct RedeemPeopleInviteResponseDTO: Decodable {
    let ok: Bool
    let invite: PeopleInviteDTO
}
