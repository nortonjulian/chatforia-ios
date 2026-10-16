import Foundation

struct BadgeStateDTO: Decodable, Equatable {
    let unreadConversations: Int
    let missedCalls: Int
    let unreadVoicemails: Int
    let total: Int
}

final class BadgeStateService {
    static let shared = BadgeStateService()

    private init() {}

    func fetchBadgeState(token: String) async throws -> BadgeStateDTO {
        try await APIClient.shared.send(
            APIRequest(
                path: "badge-state",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )
    }
}
