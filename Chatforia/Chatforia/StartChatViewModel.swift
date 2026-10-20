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
    
    private var appLanguage: String {
        UserDefaults.standard.string(
            forKey: "chatforia_language"
        ) ?? "en"
    }

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
        return appText(
            "ios.unknown_contact",
            languageCode: appLanguage
        )
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
            return "sms-\(conversation.id ?? 0)"
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
    @Published var conversationResults: [ConversationDTO] = []
    private var searchVersion = 0
    private var conversationResultsToken: String?

    @Published var isGroupMode: Bool = false
    @Published var groupName: String = ""
    @Published var selectedGroupUsers: [UserSearchResultDTO] = []
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPhoneCandidate: String? {
        Self.normalizePhone(trimmedQuery)
    }

    var looksLikePhoneInput: Bool {
        normalizedPhoneCandidate != nil
    }

    func handleSearchTextChanged(currentUserId: Int?) {
        searchTask?.cancel()
        searchVersion += 1
        results = []
        contactResults = []
        conversationResults = []
        conversationResultsToken = nil
        errorText = nil

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
                    await self.searchExistingConversations(query: query)
                    guard !Task.isCancelled else { return }
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
                await self.searchExistingConversations(query: query)
                guard !Task.isCancelled else { return }
                await self.searchUsers(query: query, currentUserId: currentUserId)
            } catch {
                return
            }
        }
    }
    

    func searchUsers(query: String, currentUserId: Int?) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
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

        let version = searchVersion
        isLoading = true
        errorText = nil
        defer { if version == searchVersion { isLoading = false } }

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
            debugLog("❌ contact search error:", error)
        }

        guard version == searchVersion, !Task.isCancelled,
              TokenStore.shared.read() == token else { return }
        results = fetchedUsers
        contactResults = fetchedContacts

        if !hadAnySuccess {
            errorText = appText(
                "startChat.fetchResultsFailed",
                languageCode: appLanguage
            )
        } else if userSearchFailed {
            errorText = nil
        } else {
            errorText = nil
        }
    }
    
    func searchContactsOnly(query: String) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            contactResults = []
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            contactResults = []
            errorText = nil
            return
        }

        let version = searchVersion
        isLoading = true
        errorText = nil
        defer { if version == searchVersion { isLoading = false } }

        do {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed

            let contacts: ContactsResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "contacts?q=\(encoded)&limit=20", method: .GET, requiresAuth: true),
                token: token
            )

            guard version == searchVersion, !Task.isCancelled,
                  TokenStore.shared.read() == token else { return }
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
            guard version == searchVersion, !Task.isCancelled,
                  TokenStore.shared.read() == token else { return }
            errorText = appText(
                "startChat.fetchContactsFailed",
                languageCode: appLanguage
            )
            contactResults = []
        }
    }
    
    func searchExistingConversations(query: String) async {
        guard !isGroupMode else { return }
        guard let token = TokenStore.shared.read(), !token.isEmpty else { return }
        let version = searchVersion
        isLoading = true
        defer { if version == searchVersion { isLoading = false } }
        do {
            struct Response: Decodable {
                let items: [ConversationDTO]?
                let conversations: [ConversationDTO]?
            }
            let response: Response = try await APIClient.shared.send(
                APIRequest(path: "conversations?t=\(Int(Date().timeIntervalSince1970 * 1000))",
                           method: .GET, requiresAuth: true), token: token)
            guard version == searchVersion, !Task.isCancelled,
                  TokenStore.shared.read() == token else { return }
            conversationResultsToken = token
            conversationResults = (response.items ?? response.conversations ?? []).filter {
                ($0.id ?? 0) > 0 && ($0.kind.lowercased() == "chat" || $0.kind.lowercased() == "sms") &&
                $0.isRandomChat != true && $0.randomChat == nil &&
                ConversationLookup.matches($0, query: query)
            }
        } catch {
            // People and contact search remain available if this read fails.
            guard version == searchVersion, !Task.isCancelled,
                  TokenStore.shared.read() == token else { return }
            conversationResults = []
        }
    }

    func destinationForExistingConversation(_ conversation: ConversationDTO) throws -> StartDestination {
        guard let token = TokenStore.shared.read(), !token.isEmpty,
              token == conversationResultsToken,
              conversationResults.contains(where: { $0.uniqueId == conversation.uniqueId }),
              let id = conversation.id, id > 0 else { throw APIError.unauthorized }
        if conversation.kind.lowercased() == "sms" { return .sms(conversation) }
        guard conversation.kind.lowercased() == "chat", let room = conversation.asChatRoomDTO else {
            throw APIError.unauthorized
        }
        return .chat(room)
    }

    func destinationForContactResult(_ contact: ContactSearchResultDTO) async throws -> StartDestination {
        if let userId = contact.user?.id ?? contact.userId {
            return try await createOrOpenDirectChat(targetUserId: userId, displayName: contact.displayName)
        }

        if let phone = contact.externalPhone, !phone.isEmpty {
            guard let token = TokenStore.shared.read(), !token.isEmpty else {
                throw APIError.unauthorized
            }

            let conversation = try await ChatRoomService.shared.startSMSThread(
                phone: phone, contactId: contact.id, displayName: contact.displayName, token: token)
            return .sms(conversation)
        }

        throw NSError(
            domain: "StartChatViewModel",
            code: 99,
            userInfo: [
                NSLocalizedDescriptionKey: appText(
                    "startChat.contactOpenFailed",
                    languageCode: appLanguage
                )
            ]
        )
    }

    func createOrOpenDirectChat(targetUserId: Int, displayName: String? = nil) async throws -> StartDestination {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        isCreating = true
        errorText = nil
        defer { isCreating = false }

        let room = try await ChatRoomService.shared.startDirectChat(
            userId: targetUserId,
            token: token,
            displayName: displayName
        )

        return .chat(room)
    }

    func createOrOpenExistingSMSThread() async throws -> StartDestination {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        guard let normalized = normalizedPhoneCandidate else {
            throw NSError(
                domain: "StartChatViewModel",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: appText(
                        "startChat.enterValidPhone",
                        languageCode: appLanguage
                    )
                ]
            )
        }

        isCreating = true
        errorText = nil
        defer { isCreating = false }

        let conversation = try await ChatRoomService.shared.startSMSThread(phone: normalized, token: token)
        return .sms(conversation)
    }

    var canCreateGroup: Bool {
        selectedGroupUsers.count >= 2
    }

    func isSelectedForGroup(userId: Int) -> Bool {
        selectedGroupUsers.contains { $0.id == userId }
    }

    func toggleGroupUser(_ user: UserSearchResultDTO) {
        if let index = selectedGroupUsers.firstIndex(where: { $0.id == user.id }) {
            selectedGroupUsers.remove(at: index)
        } else {
            selectedGroupUsers.append(user)
        }
    }

    func toggleGroupContact(_ contact: ContactSearchResultDTO) {
        guard let userId = contact.user?.id ?? contact.userId else { return }

        let username =
            contact.user?.username ??
            contact.alias ??
            contact.externalName ??
            "User \(userId)"

        toggleGroupUser(
            UserSearchResultDTO(
                id: userId,
                username: username,
                avatarUrl: nil
            )
        )
    }

    func resetGroupSelection() {
        groupName = ""
        selectedGroupUsers = []
    }

    func createGroupChat() async throws -> StartDestination {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            throw APIError.unauthorized
        }

        guard canCreateGroup else {
            throw NSError(
                domain: "StartChatViewModel",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Select at least 2 people for a group chat."
                ]
            )
        }

        isCreating = true
        errorText = nil
        defer { isCreating = false }

        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)

        let room = try await ChatRoomService.shared.createGroupChat(
            userIds: selectedGroupUsers.map { $0.id },
            name: trimmedName.isEmpty ? nil : trimmedName,
            token: token
        )

        resetGroupSelection()
        return .chat(room)
    }

    static func normalizePhone(_ input: String) -> String? {
        ConversationLookup.normalizePhone(input)
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
