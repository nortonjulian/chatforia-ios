import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var conversations: [ConversationDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var searchText: String = ""

    @Published private(set) var hasCompletedInitialLoad = false

    private var initialLoadToken: String?
    private var isInitialLoadInProgress = false
    
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

    func isInitialLoadComplete(for token: String?) -> Bool {
        guard let token = token?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        !token.isEmpty else {
            return false
        }

        return hasCompletedInitialLoad &&
            initialLoadToken == token
    }

    func loadInitialConversationsIfNeeded(token: String?) async {
        guard let token = token?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        !token.isEmpty else {
            return
        }

        // A different token means a different signed-in session.
        // Never display conversations left over from another session.
        if initialLoadToken != token {
            initialLoadToken = token
            conversations = []
            errorText = nil
            searchText = ""
            hasCompletedInitialLoad = false
        }

        guard !hasCompletedInitialLoad,
            !isInitialLoadInProgress else {
            return
        }

        isInitialLoadInProgress = true

        defer {
            isInitialLoadInProgress = false
            hasCompletedInitialLoad = true
        }

        await loadConversations(token: token)
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

            let merged = preserveExistingPreviewWhenBackendHasPlaceholder(hydrated)
            self.conversations = sortedConversations(merged)

            for convo in self.conversations
                where shouldHydrateEncryptedPreview(convo) {

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

    func deleteConversation(
        _ conversation: ConversationDTO,
        token: String?
    ) async {
        guard let token, !token.isEmpty else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return
        }

        guard let conversationId = conversation.id else {
            errorText = "Missing conversation id."
            return
        }

        let normalizedKind = conversation.kind.lowercased()

        do {
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(normalizedKind)/\(conversationId)",
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
            )

            if normalizedKind == "chat" {
                let cachedMessageIds = MessageStore.shared.currentWindow()
                    .filter { $0.chatRoomId == conversationId }
                    .map(\.id)
                    .filter { $0 > 0 }

                for messageId in cachedMessageIds {
                    DecryptedMessageTextStore.shared.removeText(
                        for: messageId
                    )
                }

                MessageStore.shared.removeMessages(
                    forRoomId: conversationId
                )
            }

            conversations.removeAll {
                $0.id == conversation.id &&
                $0.kind.lowercased() == normalizedKind
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

            let targetMessageId = conversation.last?.messageId

            let newest: MessageDTO?

            if let targetMessageId {
                newest =
                    page.items.first(where: { $0.id == targetMessageId })
                    ?? page.items.first
            } else {
                newest = page.items.first
            }

            guard let newest else { return }

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
                let payload = newest.encryptedPayloadForMe,
                !payload.contentCiphertext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                let currentUserId =
                    UserDefaults.standard.integer(
                        forKey: "chatforia.currentUserId"
                    )

                guard currentUserId > 0 else { return }

                decrypted =
                    try MessageCryptoService.shared
                        .decryptMessageForCurrentBackend(
                            ciphertextBase64: payload.contentCiphertext,
                            encryptedKeyPayload: payload.encryptedKey,
                            userId: currentUserId
                        )

                await MainActor.run {
                    DecryptedMessageTextStore.shared
                        .setText(decrypted, for: newest.id)
                }

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
                debugLog(
                    "⚠️ preview hydrate no decryptable content",
                    "messageId=", newest.id,
                    "hasEncryptedPayloadForMe=", newest.encryptedPayloadForMe != nil,
                    "hasContentCiphertext=", newest.contentCiphertext != nil,
                    "hasEncryptedKeyForMe=", newest.encryptedKeyForMe != nil
                )
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

                self.resortConversations()
            }
        } catch {
            debugLog("⚠️ preview hydrate failed:", error.localizedDescription)
        }
    }

    private func shouldHydrateEncryptedPreview(_ conversation: ConversationDTO) -> Bool {
        guard conversation.kind.lowercased() == "chat" else { return false }
        guard conversation.id != nil else { return false }

        let text =
            conversation.last?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        if text.isEmpty {
            return true
        }

        return text.localizedCaseInsensitiveCompare("Message") == .orderedSame
    }

    private func preserveExistingPreviewWhenBackendHasPlaceholder(
        _ incomingConversations: [ConversationDTO]
    ) -> [ConversationDTO] {
        incomingConversations.map { incoming in
            guard incoming.kind.lowercased() == "chat" else {
                return incoming
            }

            let incomingText =
                incoming.last?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            let incomingIsPlaceholder =
                incomingText.isEmpty ||
                incomingText.localizedCaseInsensitiveCompare("Message") == .orderedSame

            guard incomingIsPlaceholder else {
                return incoming
            }

            guard let existing = conversations.first(where: { $0.uniqueId == incoming.uniqueId }) else {
                return incoming
            }

            guard let existingLast = existing.last else {
                return incoming
            }

            let existingText =
                existingLast.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            guard !existingText.isEmpty else {
                return incoming
            }

            guard existingText.localizedCaseInsensitiveCompare("Message") != .orderedSame else {
                return incoming
            }

            if let incomingMessageId = incoming.last?.messageId,
            let existingMessageId = existingLast.messageId,
            incomingMessageId != existingMessageId {
                return incoming
            }

            return ConversationDTO(
                kind: incoming.kind,
                id: incoming.id,
                title: incoming.title,
                displayName: incoming.displayName,
                updatedAt: incoming.updatedAt,
                isGroup: incoming.isGroup,
                phone: incoming.phone,
                unreadCount: incoming.unreadCount,
                avatarUsers: incoming.avatarUsers,
                last: ConversationLastDTO(
                    text: existingText,
                    messageId: incoming.last?.messageId ?? existingLast.messageId,
                    at: incoming.last?.at ?? existingLast.at,
                    hasMedia: incoming.last?.hasMedia ?? existingLast.hasMedia,
                    mediaCount: incoming.last?.mediaCount ?? existingLast.mediaCount,
                    mediaKinds: incoming.last?.mediaKinds ?? existingLast.mediaKinds,
                    thumbUrl: incoming.last?.thumbUrl ?? existingLast.thumbUrl,
                    senderName: incoming.last?.senderName ?? existingLast.senderName
                )
            )
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
