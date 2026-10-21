import Foundation

final class ChatRoomService {
    static let shared = ChatRoomService()
    private init() {}

    func startDirectChat(
        userId: Int,
        token: String,
        displayName: String? = nil
    ) async throws -> ChatRoomDTO {
        let room: DirectChatRoomResponseDTO = try await APIClient.shared.send(
            APIRequest(
                path: "chatrooms/direct/\(userId)",
                method: .POST,
                requiresAuth: true
            ),
            token: token
        )

        let dto = room.asChatRoomDTO
        let targetName = room.participants?.compactMap { $0.user }
            .first(where: { $0.id == userId })?.username
        let name = [displayName, targetName, dto.name].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }.first
        return ChatRoomDTO(id: dto.id, name: name, isGroup: dto.isGroup,
            updatedAt: dto.updatedAt, phone: dto.phone, lastMessage: dto.lastMessage,
            participants: dto.participants)
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

extension ChatRoomService {
    func startSMSThread(phone: String, contactId: Int? = nil,
                        displayName: String? = nil, token: String) async throws -> ConversationDTO {
        guard let phone = ConversationLookup.normalizePhone(phone) else {
            throw NSError(domain: "ConversationRouting", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Enter a valid phone number."])
        }
        struct Body: Encodable { let phone: String; let contactId: Int? }
        let body = try JSONEncoder().encode(Body(phone: phone, contactId: contactId))
        let thread: SMSStartThreadResponseDTO = try await APIClient.shared.send(
            APIRequest(path: "sms/threads/start", method: .POST, body: body, requiresAuth: true),
            token: token)
        guard thread.id > 0 else {
            throw NSError(domain: "ConversationRouting", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not open the conversation."])
        }
        let title = [displayName, thread.displayName, thread.contactName, thread.contactPhone, phone]
            .compactMap { value -> String? in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else { return nil }
                return value
            }.first ?? phone
        return ConversationDTO(kind: "sms", id: thread.id, title: title, displayName: title,
            updatedAt: thread.updatedAt, isGroup: false, phone: thread.contactPhone ?? phone,
            unreadCount: nil, avatarUsers: nil, last: nil)
    }
}
