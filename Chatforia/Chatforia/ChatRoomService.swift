import Foundation

final class ChatRoomService {
    static let shared = ChatRoomService()
    private init() {}

    func startDirectChat(
        userId: Int,
        token: String
    ) async throws -> ChatRoomDTO {
        let room: DirectChatRoomResponseDTO = try await APIClient.shared.send(
            APIRequest(
                path: "chatrooms/direct/\(userId)",
                method: .POST,
                requiresAuth: true
            ),
            token: token
        )

        return room.asChatRoomDTO
    }

    func createGroupChat(
        userIds: [Int],
        name: String?,
        token: String
    ) async throws -> ChatRoomDTO {
        struct Body: Encodable {
            let userIds: [Int]
            let name: String?
        }

        let body = try JSONEncoder().encode(
            Body(userIds: userIds, name: name)
        )

        let room: ChatRoomDTO = try await APIClient.shared.send(
            APIRequest(
                path: "chatrooms/group",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )

        return room
    }
}
