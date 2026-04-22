import Foundation
import Combine

struct UserSearchResultDTO: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let avatarUrl: String?
}

struct DirectChatRoomResponseDTO: Decodable {
    let id: Int
    let isGroup: Bool?
    let updatedAt: String?
    let participants: [DirectChatParticipantDTO]?
}

struct DirectChatParticipantDTO: Decodable {
    let userId: Int?
    let role: String?
    let user: UserPreviewDTO?

    enum CodingKeys: String, CodingKey {
        case userId
        case role
        case user
    }
}

struct SMSStartThreadResponseDTO: Decodable {
    let id: Int
    let contactPhone: String?
    let displayName: String?
    let contactName: String?
    let updatedAt: String?
}

struct ContactSearchResultDTO: Codable, Identifiable, Equatable {
    let id: Int
    let alias: String?
    let favorite: Bool?
    let externalPhone: String?
    let externalName: String?
    let createdAt: Date?
    let userId: Int?
    let user: ContactUserDTO?

    var displayName: String {
        if let alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return alias
        }
        if let username = user?.username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        if let externalName, !externalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return externalName
        }
        if let externalPhone, !externalPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return externalPhone
        }
        return "Unknown Contact"
    }
}

enum StartDestination: Identifiable {
    case chat(ChatRoomDTO)
    case sms(ConversationDTO)

    var id: String {
        switch self {
        case .chat(let room):
            return "chat-\(room.id)"
        case .sms(let conversation):
            return "sms-\(conversation.id)"
        }
    }
}

@MainActor
final class StartChatViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [UserSearchResultDTO] = []
    @Published var isLoading: Bool = false
    @Published var isCreating: Bool = false
    @Published var errorText: String?
    @Published var contactResults: [ContactSearchResultDTO] = []

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPhoneCandidate: String? {
        Self.normalizePhone(trimmedQuery)
    }

    var looksLikePhoneInput: Bool {
        let raw = trimmedQuery
        guard !raw.isEmpty else { return false }
        let digits = raw.filter(\.isNumber)
        return digits.count >= 7
    }

    func handleSearchTextChanged(currentUserId: Int?) {
        searchTask?.cancel()

        let query = trimmedQuery
        guard !query.isEmpty else {
            results = []
            contactResults = []
            errorText = nil
            isLoading = false
            return
        }

        if looksLikePhoneInput {
            searchTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                    await self.searchContactsOnly(query: query)
                } catch {
                    return
                }
            }
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                await self.searchUsers(query: query, currentUserId: currentUserId)
            } catch {
                return
            }
        }
    }
    

    func searchUsers(query: String, currentUserId: Int?) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            errorText = "Missing auth token."
            results = []
            contactResults = []
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            contactResults = []
            errorText = nil
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed

        var fetchedUsers: [UserSearchResultDTO] = []
        var fetchedContacts: [ContactSearchResultDTO] = []
        var hadAnySuccess = false
        var userSearchFailed = false

        do {
            let users: [UserSearchResultDTO] = try await APIClient.shared.send(
                APIRequest(path: "users/search?query=\(encoded)", method: .GET, requiresAuth: true),
                token: token
            )

            fetchedUsers = currentUserId != nil
                ? users.filter { $0.id != currentUserId }
                : users

            hadAnySuccess = true
        } catch {
            userSearchFailed = true
            print("❌ user search error:", error)
        }

        do {
            let contacts: ContactsResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "contacts?q=\(encoded)&limit=20", method: .GET, requiresAuth: true),
                token: token
            )

            fetchedContacts = contacts.items.map {
                ContactSearchResultDTO(
                    id: $0.id,
                    alias: $0.alias,
                    favorite: $0.favorite,
                    externalPhone: $0.externalPhone,
                    externalName: $0.externalName,
                    createdAt: $0.createdAt,
                    userId: $0.userId,
                    user: $0.user
                )
            }

            hadAnySuccess = true
        } catch {
            print("❌ contact search error:", error)
        }

        results = fetchedUsers
        contactResults = fetchedContacts

        if !hadAnySuccess {
            errorText = "Unable to fetch results. Please try again."
        } else if userSearchFailed {
            errorText = nil
        } else {
            errorText = nil
        }
    }
    
    func searchContactsOnly(query: String) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            errorText = "Missing auth token."
            contactResults = []
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            contactResults = []
            errorText = nil
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed

            let contacts: ContactsResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "contacts?q=\(encoded)&limit=20", method: .GET, requiresAuth: true),
                token: token
            )

            contactResults = contacts.items.map {
                ContactSearchResultDTO(
                    id: $0.id,
                    alias: $0.alias,
                    favorite: $0.favorite,
                    externalPhone: $0.externalPhone,
                    externalName: $0.externalName,
                    createdAt: $0.createdAt,
                    userId: $0.userId,
                    user: $0.user
                )
            }

            results = [] // 👈 important: hide user results in phone mode
        } catch {
            errorText = "Unable to fetch contacts."
            contactResults = []
            print("❌ searchContactsOnly error:", error)
        }
    }
    
    func destinationForContactResult(_ contact: ContactSearchResultDTO) async throws -> StartDestination {
        if let userId = contact.user?.id ?? contact.userId {
            return try await createOrOpenDirectChat(targetUserId: userId)
        }

        if let phone = contact.externalPhone, !phone.isEmpty {
            guard let token = TokenStore.shared.read(), !token.isEmpty else {
                throw APIError.unauthorized
            }

            struct Request: Encodable {
                let phone: String
                let contactId: Int?
            }

            let body = try JSONEncoder().encode(
                Request(phone: phone, contactId: contact.id)
            )

            let thread: SMSStartThreadResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "sms/threads/start", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            let resolvedTitle = thread.displayName ?? thread.contactName ?? thread.contactPhone ?? phone

            let conversation = ConversationDTO(
                kind: "sms",
                id: thread.id,
                title: resolvedTitle,
                displayName: resolvedTitle,
                updatedAt: thread.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
                isGroup: false,
                phone: thread.contactPhone ?? phone,
                unreadCount: 0,
                avatarUsers: [
                    ConversationAvatarUserDTO(
                        id: 0,
                        username: resolvedTitle,
                        displayName: resolvedTitle,
                        avatarUrl: nil
                    )
                ],
                last: nil
            )

            return .sms(conversation)
        }

        throw NSError(
            domain: "StartChatViewModel",
            code: 99,
            userInfo: [NSLocalizedDescriptionKey: "This contact could not be opened."]
        )
    }

    func createOrOpenDirectChat(targetUserId: Int) async throws -> StartDestination {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        isCreating = true
        errorText = nil
        defer { isCreating = false }

        let room: DirectChatRoomResponseDTO = try await APIClient.shared.send(
            APIRequest(path: "chatrooms/direct/\(targetUserId)", method: .POST, requiresAuth: true),
            token: token
        )

        return .chat(room.asChatRoomDTO)
    }

    func createOrOpenExistingSMSThread() async throws -> StartDestination {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        guard let normalized = normalizedPhoneCandidate else {
            throw NSError(
                domain: "StartChatViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Enter a valid phone number."]
            )
        }

        isCreating = true
        errorText = nil
        defer { isCreating = false }

        struct Request: Encodable {
            let phone: String
        }

        let body = try JSONEncoder().encode(Request(phone: normalized))

        let thread: SMSStartThreadResponseDTO = try await APIClient.shared.send(
            APIRequest(path: "sms/threads/start", method: .POST, body: body, requiresAuth: true),
            token: token
        )

        let resolvedTitle = thread.displayName ?? thread.contactName ?? thread.contactPhone ?? normalized

        let conversation = ConversationDTO(
            kind: "sms",
            id: thread.id,
            title: resolvedTitle,
            displayName: resolvedTitle,
            updatedAt: thread.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
            isGroup: false,
            phone: thread.contactPhone ?? normalized,
            unreadCount: 0,
            avatarUsers: [
                ConversationAvatarUserDTO(
                    id: 0,
                    username: resolvedTitle,
                    displayName: resolvedTitle,
                    avatarUrl: nil
                )
            ],
            last: nil
        )

        return .sms(conversation)
    }

    static func normalizePhone(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hasLeadingPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)

        guard digits.count >= 7 else { return nil }

        if hasLeadingPlus {
            return "+\(digits)"
        }

        if digits.count == 10 {
            return "+1\(digits)"
        }

        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }

        return "+\(digits)"
    }
}

extension DirectChatRoomResponseDTO {
    var asChatRoomDTO: ChatRoomDTO {
        ChatRoomDTO(
            id: id,
            name: nil,
            isGroup: isGroup,
            updatedAt: updatedAt,
            phone: nil,
            lastMessage: nil,
            participants: participants?
                .compactMap { $0.user }
                .map {
                    UserPreviewDTO(
                        id: $0.id,
                        username: $0.username
                    )
                }
        )
    }
}
