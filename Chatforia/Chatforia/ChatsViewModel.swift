import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var conversations: [ConversationDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var searchText: String = ""
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }
    
    private var cancellables = Set<AnyCancellable>()

    static let conversationsBasePath = "conversations"

    init() {
        NotificationCenter.default.publisher(for: .socketMessageUpsert)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let payload = note.userInfo?["payload"] as? [String: Any] else { return }

                let raw =
                    (payload["item"] as? [String: Any]) ??
                    (payload["shaped"] as? [String: Any]) ??
                    (payload["message"] as? [String: Any]) ??
                    payload

                let item = payload["item"] as? [String: Any]
                let message = payload["message"] as? [String: Any]
                let shaped = payload["shaped"] as? [String: Any]

                let roomIdFromRawInt = raw["chatRoomId"] as? Int ?? raw["roomId"] as? Int
                let roomIdFromRawString =
                    (raw["chatRoomId"] as? String).flatMap(Int.init) ??
                    (raw["roomId"] as? String).flatMap(Int.init)

                let roomIdFromItem = item?["chatRoomId"] as? Int ?? item?["roomId"] as? Int
                let roomIdFromMessage = message?["chatRoomId"] as? Int ?? message?["roomId"] as? Int
                let roomIdFromShaped = shaped?["chatRoomId"] as? Int ?? shaped?["roomId"] as? Int

                let roomId =
                    roomIdFromRawInt ??
                    roomIdFromRawString ??
                    roomIdFromItem ??
                    roomIdFromMessage ??
                    roomIdFromShaped

                guard let roomId else { return }

                if let deletedForMe = raw["deletedForMe"] as? Bool, deletedForMe == true {
                    return
                }

                self.bumpConversation(roomId: roomId, payload: raw)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .socketMessageEdited)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let payload = note.userInfo?["payload"] as? [String: Any] else { return }

                let raw =
                    (payload["item"] as? [String: Any]) ??
                    (payload["shaped"] as? [String: Any]) ??
                    (payload["message"] as? [String: Any]) ??
                    payload

                guard
                    let roomId = raw["chatRoomId"] as? Int,
                    let messageId = raw["id"] as? Int,
                    let index = self.conversations.firstIndex(where: { $0.id == roomId })
                else { return }

                let currentLastMessageId = self.conversations[index].last?.messageId
                guard currentLastMessageId == messageId else { return }

                self.bumpConversation(roomId: roomId, payload: raw)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .MessagesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                for index in self.conversations.indices {
                    guard let messageId = self.conversations[index].last?.messageId,
                          let decrypted = DecryptedMessageTextStore.shared.text(for: messageId)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !decrypted.isEmpty
                    else { continue }

                    let convo = self.conversations[index]
                    let last = convo.last

                    self.conversations[index] = ConversationDTO(
                        kind: convo.kind,
                        id: convo.id,
                        title: convo.title,
                        displayName: convo.displayName,
                        updatedAt: convo.updatedAt,
                        isGroup: convo.isGroup,
                        phone: convo.phone,
                        unreadCount: convo.unreadCount,
                        avatarUsers: convo.avatarUsers,
                        last: ConversationLastDTO(
                            text: decrypted,
                            messageId: last?.messageId,
                            at: last?.at,
                            hasMedia: last?.hasMedia,
                            mediaCount: last?.mediaCount,
                            mediaKinds: last?.mediaKinds,
                            thumbUrl: last?.thumbUrl,
                            senderName: last?.senderName
                        )
                    )
                }

                self.resortConversations()
            }
            .store(in: &cancellables)
    }
    
    private func bumpConversation(roomId: Int, payload: [String: Any]) {
    guard let index = conversations.firstIndex(where: { $0.id == roomId }) else {
        Task {
            await self.loadConversations(token: TokenStore.shared.read())
        }
        return
    }

        let convo = conversations[index]
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let currentLast = convo.last

        let newText: String? = {
            if let ciphertext = payload["contentCiphertext"] as? String {
                if let messageId = payload["id"] as? Int,
                   let decrypted = DecryptedMessageTextStore.shared.text(for: messageId)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !decrypted.isEmpty {
                    return decrypted
                }

                if let encryptedKeyPayload = payload["encryptedKeyForMe"] as? String {
                    let currentUserId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")

                    if currentUserId > 0,
                       let messageId = payload["id"] as? Int,
                       let decrypted = try? MessageCryptoService.shared.decryptMessageForCurrentBackend(
                            ciphertextBase64: ciphertext,
                            encryptedKeyPayload: encryptedKeyPayload,
                            userId: currentUserId
                       ) {
                        DecryptedMessageTextStore.shared.setText(decrypted, for: messageId)
                        return decrypted
                    }
                }

                return "Message"
            }

            if let text = payload["rawContent"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }

            if let text = payload["translatedForMe"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }

            if let clientMessageId = payload["clientMessageId"] as? String,
               let localMessage = MessageStore.shared.currentWindow()
                .first(where: { $0.clientMessageId == clientMessageId }) {
                return localMessage.rawContent
                    ?? localMessage.translatedForMe
            }

            if payload["deletedForAll"] as? Bool == true {
                return String(localized: "messages.messageDeleted")
            }

            if let attachments = payload["attachments"] as? [[String: Any]], !attachments.isEmpty {
                return "[media]"
            }

            return currentLast?.text
        }()

        let hasMedia: Bool = {
            if let attachments = payload["attachments"] as? [[String: Any]] {
                return !attachments.isEmpty
            }
            return currentLast?.hasMedia ?? false
        }()

        let mediaCount: Int? = {
            if let attachments = payload["attachments"] as? [[String: Any]] {
                return attachments.count
            }
            return currentLast?.mediaCount
        }()

        let mediaKinds: [String]? = {
            if let attachments = payload["attachments"] as? [[String: Any]] {
                let kinds = attachments.compactMap { $0["kind"] as? String }
                return kinds.isEmpty ? currentLast?.mediaKinds : kinds
            }
            return currentLast?.mediaKinds
        }()

        let thumbUrl: String? = {
            if let attachments = payload["attachments"] as? [[String: Any]] {
                for att in attachments {
                    if let thumb = att["thumbUrl"] as? String, !thumb.isEmpty {
                        return thumb
                    }
                    if let url = att["url"] as? String, !url.isEmpty {
                        return url
                    }
                }
            }
            return currentLast?.thumbUrl
        }()

        let messageId: Int? = {
            if let id = payload["id"] as? Int, id > 0 {
                return id
            }
            return currentLast?.messageId
        }()

        let newLast = ConversationLastDTO(
            text: newText,
            messageId: messageId,
            at: nowISO,
            hasMedia: hasMedia,
            mediaCount: mediaCount,
            mediaKinds: mediaKinds,
            thumbUrl: thumbUrl,
            senderName: currentLast?.senderName
        )

        let updated = ConversationDTO(
            kind: convo.kind,
            id: convo.id,
            title: convo.title,
            displayName: convo.displayName,
            updatedAt: nowISO,
            isGroup: convo.isGroup,
            phone: convo.phone,
            unreadCount: convo.unreadCount,
            avatarUsers: convo.avatarUsers,
            last: newLast
        )

        conversations[index] = updated
        resortConversations()
    }
    
    private func resortConversations() {
        conversations = sortedConversations(conversations)
    }

    private func searchableTitle(for item: ConversationDTO) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallbackTitle(for: item) : title
    }

    private func fallbackTitle(for item: ConversationDTO) -> String {
        let id = item.id ?? 0

        switch item.kind.lowercased() {
        case "sms":
            if let phone = item.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                return phone
            }
            return String(format: String(localized: "sms.threadNumber"), id)
        default:
            return String(format: String(localized: "chat.roomNumber"), id)
        }
    }

    var filteredConversations: [ConversationDTO] {
        let base = sortedConversations(conversations)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }

        return base.filter { item in
            let title = searchableTitle(for: item).lowercased()
            let phone = item.phone?.lowercased() ?? ""
            let lastText = item.last?.text?.lowercased() ?? ""

            return title.contains(query)
                || phone.contains(query)
                || lastText.contains(query)
        }
    }

    func loadConversations(token: String?) async {
        guard let token else {
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
            conversations = []
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response: ConversationsResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "\(Self.conversationsBasePath)?t=\(Int(Date().timeIntervalSince1970 * 1000))",
                    method: .GET,
                    requiresAuth: true
                ),
                token: token
            )

            let fetched = response.conversations ?? response.items ?? []

            let hydrated = fetched.map { convo in
                guard let last = convo.last,
                      let messageId = last.messageId,
                      let decrypted = DecryptedMessageTextStore.shared.text(for: messageId)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !decrypted.isEmpty
                else {
                    return convo
                }

                return ConversationDTO(
                    kind: convo.kind,
                    id: convo.id,
                    title: convo.title,
                    displayName: convo.displayName,
                    updatedAt: convo.updatedAt,
                    isGroup: convo.isGroup,
                    phone: convo.phone,
                    unreadCount: convo.unreadCount,
                    avatarUsers: convo.avatarUsers,
                    last: ConversationLastDTO(
                        text: decrypted,
                        messageId: last.messageId,
                        at: last.at,
                        hasMedia: last.hasMedia,
                        mediaCount: last.mediaCount,
                        mediaKinds: last.mediaKinds,
                        thumbUrl: last.thumbUrl,
                        senderName: last.senderName
                    )
                )
            }

            self.conversations = sortedConversations(hydrated)

            for convo in self.conversations
                where convo.last?.text == "Message" {

                Task {
                    await self.hydrateEncryptedPreview(
                        conversation: convo,
                        token: token
                    )
                }
            }
            
            SocketManager.shared.connect(token: token)

            for convo in fetched where convo.kind.lowercased() == "chat" {
                if let roomId = convo.id {
                    SocketManager.shared.joinRoom(roomId)
                }
            }
            
        } catch {
            errorText = error.localizedDescription
        }
    }

    func archiveConversation(_ conversation: ConversationDTO, token: String?) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
            return false
        }

        guard let conversationId = conversation.id else {
            errorText = String(localized: "chat.missingConversationId")
            return false
        }

        struct ArchiveRequest: Encodable {
            let archived: Bool
        }

        do {
            let body = try JSONEncoder().encode(ArchiveRequest(archived: true))

            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(conversation.kind.lowercased())/\(conversationId)/archive",
                    method: .PATCH,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )

            conversations.removeAll {
                $0.id == conversation.id &&
                $0.kind.lowercased() == conversation.kind.lowercased()
            }

            conversations = sortedConversations(conversations)
            errorText = nil
            return true
        } catch {
            errorText = "Failed to archive conversation."
            return false
        }
    }

    func deleteConversation(_ conversation: ConversationDTO, token: String?) async {
        guard let token else {
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
            return
        }

        guard let conversationId = conversation.id else {
            errorText = "Missing conversation id."
            return
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(conversation.kind.lowercased())/\(conversationId)",
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
            )

            conversations.removeAll {
                $0.id == conversation.id &&
                $0.kind.lowercased() == conversation.kind.lowercased()
            }

            conversations = sortedConversations(conversations)
            errorText = nil
        } catch {
            errorText = String(localized: "chat.deleteFailed")
        }
    }
    
    private func hydrateEncryptedPreview(
        conversation: ConversationDTO,
        token: String?
    ) async {

        guard let roomId = conversation.id else { return }
        guard let token, !token.isEmpty else { return }

        do {
            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "messages/\(roomId)",
                    method: .GET,
                    requiresAuth: true
                ),
                token: token
            )

            guard let targetMessageId = conversation.last?.messageId else { return }

            guard let newest = page.items.first(where: { $0.id == targetMessageId })
                ?? page.items.first
            else { return }

            let decrypted: String

            if let raw =
                newest.rawContent?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {

                decrypted = raw

            } else if let translated =
                newest.translatedForMe?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !translated.isEmpty {

                decrypted = translated

            } else if let cached =
                DecryptedMessageTextStore.shared
                    .text(for: newest.id)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !cached.isEmpty {

                decrypted = cached

            } else if
                let ciphertext = newest.contentCiphertext,
                let encryptedKeyPayload = newest.encryptedKeyForMe {

                let currentUserId =
                    UserDefaults.standard.integer(
                        forKey: "chatforia.currentUserId"
                    )

                guard currentUserId > 0 else { return }

                decrypted =
                    try MessageCryptoService.shared
                        .decryptMessageForCurrentBackend(
                            ciphertextBase64: ciphertext,
                            encryptedKeyPayload: encryptedKeyPayload,
                            userId: currentUserId
                        )

                await MainActor.run {
                    DecryptedMessageTextStore.shared
                        .setText(decrypted, for: newest.id)
                }

            } else {
                return
            }

            await MainActor.run {

                guard let idx = self.conversations.firstIndex(
                    where: { $0.uniqueId == conversation.uniqueId }
                ) else { return }

                let convo = self.conversations[idx]

                self.conversations[idx] = ConversationDTO(
                    kind: convo.kind,
                    id: convo.id,
                    title: convo.title,
                    displayName: convo.displayName,
                    updatedAt: convo.updatedAt,
                    isGroup: convo.isGroup,
                    phone: convo.phone,
                    unreadCount: convo.unreadCount,
                    avatarUsers: convo.avatarUsers,
                    last: ConversationLastDTO(
                        text: decrypted,
                        messageId: newest.id,
                        at: newest.createdAt.ISO8601Format(),
                        hasMedia: convo.last?.hasMedia,
                        mediaCount: convo.last?.mediaCount,
                        mediaKinds: convo.last?.mediaKinds,
                        thumbUrl: convo.last?.thumbUrl,
                        senderName: convo.last?.senderName
                    )
                )
            }
        } catch {
            debugLog("⚠️ preview hydrate failed:", error.localizedDescription)
        }
    }

    private func sortedConversations(_ items: [ConversationDTO]) -> [ConversationDTO] {
        items.sorted { lhs, rhs in
            let lDate = conversationSortDate(lhs)
            let rDate = conversationSortDate(rhs)

            if lDate != rDate {
                return lDate > rDate
            }

            if lhs.id != rhs.id {
                return (lhs.id ?? 0) > (rhs.id ?? 0)
            }

            return lhs.kind.localizedCaseInsensitiveCompare(rhs.kind) == .orderedAscending
        }
    }

    private func conversationSortDate(_ item: ConversationDTO) -> Date {
        if let lastAt = parseISODate(item.last?.at) {
            return lastAt
        }
        if let updated = parseISODate(item.updatedAt) {
            return updated
        }
        return .distantPast
    }

    private func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = withFractional.date(from: trimmed) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        return plain.date(from: trimmed)
    }
}

private struct ConversationsResponse: Decodable {
    let items: [ConversationDTO]?
    let conversations: [ConversationDTO]?
}
