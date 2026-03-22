import Foundation
import Combine

struct MessagesPageResponse: Decodable {
    let items: [MessageDTO]
    let nextCursor: String?
    let nextCursorId: Int?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor
        case nextCursorId
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = try container.decode([MessageDTO].self, forKey: .items)
        count = (try? container.decode(Int.self, forKey: .count)) ?? items.count
        nextCursorId = try? container.decode(Int.self, forKey: .nextCursorId)

        if let str = try? container.decode(String.self, forKey: .nextCursor) {
            nextCursor = str
        } else if let int = try? container.decode(Int.self, forKey: .nextCursor) {
            nextCursor = String(int)
        } else {
            nextCursor = nil
        }
    }
}

struct RoomParticipantsResponse: Decodable {
    let ownerId: Int?
    let participants: [RoomParticipantDTO]
}

struct RoomParticipantDTO: Decodable {
    let userId: Int
    let role: String?
    let user: RoomParticipantUserDTO?
}

struct RoomParticipantUserDTO: Decodable {
    let id: Int
    let username: String?
    let publicKey: String?
}

struct RecipientKeyContext {
    let userId: Int
    let publicKeyBase64: String
}

struct DeviceKeyEnvelopeDTO: Codable {
    let recipientUserId: Int
    let recipientDeviceId: String
    let senderEphemeralPublicKey: String
    let wrappedMessageKey: String
    let algorithm: String
}

struct EncryptedMessagePayload {
    let ciphertextBase64: String
    let encryptedKeysByUserId: [String: String]
}

struct SendMessageRequest: Encodable {
    let chatRoomId: Int
    let content: String?
    let contentCiphertext: String?
    let encryptedKeys: [String: String]?
    let clientMessageId: String
    let attachmentsInline: [AttachmentDTO]?

    init(
        chatRoomId: Int,
        content: String? = nil,
        contentCiphertext: String? = nil,
        encryptedKeys: [String: String]? = nil,
        clientMessageId: String,
        attachmentsInline: [AttachmentDTO]? = nil
    ) {
        self.chatRoomId = chatRoomId
        self.content = content
        self.contentCiphertext = contentCiphertext
        self.encryptedKeys = encryptedKeys
        self.clientMessageId = clientMessageId
        self.attachmentsInline = attachmentsInline
    }
}

struct MessageEnvelope: Decodable {
    let item: MessageDTO?
    let shaped: MessageDTO?

    var message: MessageDTO? { item ?? shaped }
}

struct BlockUserRequest: Encodable {
    let targetUserId: Int
}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var isLoadingOlder: Bool = false
    @Published var typingUsernames: [String] = []
    @Published var isSendingImage: Bool = false

    @Published var isSubmittingReport: Bool = false
    @Published var reportErrorText: String?

    @Published private(set) var nowTick: Date = Date()
    private var expiryTask: Task<Void, Never>?

    private var typingStopTask: Task<Void, Never>?
    private var hasSentTypingStart: Bool = false

    private var socketListenerIDs: [UUID] = []
    private var activeRoomId: Int?

    private var typingLastSeen: [String: Date] = [:]
    private var typingPruneTask: Task<Void, Never>?
    private let typingTTL: TimeInterval = 4.0

    private let batchSortDebouncer = BatchSortDebouncer(debounceInterval: 0.03)

    private var cancellables = Set<AnyCancellable>()

    private var roomId: Int? = nil
    private var lastServerMessageId: Int = 0 {
        didSet {
            guard let roomId = roomId else { return }
            persistLastServerMessageId(lastServerMessageId, roomId: roomId)
        }
    }
    private var isResyncing: Bool = false

    private var currentUserId: Int?
    private var currentUsername: String?
    private var currentUserPublicKey: String?

    private var currentUserSenderDTO: SenderDTO? {
        guard let currentUserId, currentUserId > 0 else { return nil }

        return SenderDTO(
            id: currentUserId,
            username: currentUsername,
            publicKey: currentUserPublicKey,
            avatarUrl: nil
        )
    }

    init() {
        NotificationCenter.default.publisher(for: .MessagesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromMessageStore()
                self?.markVisibleMessagesRead()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .socketMessageEdited)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let payload = note.userInfo?["payload"] as? [String: Any] else { return }
                self.handleMessageEditedEvent(payload)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .socketMessageDeleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let payload = note.userInfo?["payload"] as? [String: Any] else { return }
                self.handleMessageDeletedEvent(payload)
            }
            .store(in: &cancellables)
    }

    func configureCurrentUser(id: Int?, username: String?, publicKey: String? = nil) {
        self.currentUserId = id
        self.currentUsername = username
        self.currentUserPublicKey = publicKey

        if let id {
            UserDefaults.standard.set(id, forKey: "chatforia.currentUserId")
        }
    }

    private func refreshFromMessageStore() {
        guard let roomId = self.roomId else { return }

        let snapshot = MessageStore.shared.currentWindow()
            .filter { $0.chatRoomId == roomId }
            .sorted { a, b in
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id < b.id
            }

        self.messages = snapshot
        self.objectWillChange.send()
    }

    func markVisibleMessagesRead() {
        guard let currentUserId else { return }

        let unread = messages
            .filter { $0.id > 0 }
            .filter { $0.sender.id != currentUserId }
            .filter { $0.deletedForAll != true }
            .filter { !($0.readBy?.contains(where: { $0.id == currentUserId }) ?? false) }
            .map { $0.id }

        guard !unread.isEmpty else { return }

        APIClient.shared.readMessagesBulk(unread)
    }

    func startExpiryLoop() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await MainActor.run { self.nowTick = Date() }
            }
        }
    }

    func stopExpiryLoop() {
        expiryTask?.cancel()
        expiryTask = nil
    }

    func isExpired(_ msg: MessageDTO, now: Date = Date()) -> Bool {
        guard let expires = msg.expiresAt else { return false }
        return expires <= now
    }

    func loadMessages(roomId: Int, token: String?) async {
        guard roomId > 0 else {
            errorText = "Invalid roomId (client)."
            print("❌ loadMessages called with invalid roomId:", roomId, "urlPath:", "messages/\(roomId)")
            return
        }

        guard let token else {
            errorText = "Missing auth token."
            print("❌ loadMessages missing token for roomId:", roomId)
            return
        }

        configureRoom(roomId: roomId)

        print("➡️ loadMessages: roomId=\(roomId) tokenPresent=\(token.count > 0)")
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let path = "messages/\(roomId)"

        do {
            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )

            self.messages = []
            applyToStore(page.items)
            batchSortDebouncer.flush()
            refreshFromMessageStore()
            markVisibleMessagesRead()

            if self.messages.isEmpty {
                self.errorText = "Loaded 0 messages for room \(roomId)."
                print("⚠️ loadMessages: 0 messages for roomId:", roomId)
            } else {
                print("✅ loadMessages: loaded \(self.messages.count) messages for roomId:", roomId)
            }
        } catch {
            errorText = "loadMessages: \(error.localizedDescription)"
            print("❌ loadMessages error for roomId \(roomId):", error)
        }
    }

    func loadOlderMessagesIfNeeded(limit: Int = 50) async {
        guard let roomId = self.roomId, roomId > 0 else { return }
        guard !isLoadingOlder else { return }

        errorText = nil

        guard let beforeId = MessageStore.shared.serverBeforeIdForPaging() else {
            print("⚠️ loadOlderMessagesIfNeeded: no oldest message in memory to page before.")
            return
        }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        print("➡️ loadOlderMessagesIfNeeded: roomId=\(roomId) beforeId=\(beforeId) limit=\(limit)")

        guard let token = TokenStore.shared.read() as String? else {
            print("❌ loadOlderMessagesIfNeeded: missing token")
            return
        }

        do {
            let path = "messages/\(roomId)?cursorId=\(beforeId)&limit=\(limit)"
            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )

            guard !page.items.isEmpty else {
                print("➡️ loadOlderMessagesIfNeeded: server returned 0 older items")
                return
            }

            applyToStore(page.items)
            batchSortDebouncer.flush()
            refreshFromMessageStore()
            markVisibleMessagesRead()

            errorText = nil

            print("✅ loadOlderMessagesIfNeeded: inserted \(page.items.count) older messages")
        } catch {
            print("❌ loadOlderMessagesIfNeeded error:", error)
            self.errorText = "loadOlderMessagesIfNeeded: \(error.localizedDescription)"
        }
    }

    func sendMessage(
        roomId: Int,
        token: String?,
        text: String,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        errorText = nil
        stopTypingNow(roomId: roomId)

        let clientMessageId = UUID().uuidString
        let localId = -abs(clientMessageId.hashValue)

        let sender = SenderDTO(
            id: senderId,
            username: senderUsername,
            publicKey: senderPublicKey,
            avatarUrl: nil
        )

        let optimistic = MessageDTO.optimistic(
            roomId: roomId,
            clientMessageId: clientMessageId,
            localId: localId,
            text: trimmed,
            senderId: sender.id,
            senderUsername: sender.username,
            senderPublicKey: sender.publicKey
        )

        applyToStore(optimistic)
        MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .sending)
        refreshFromMessageStore()

        let bodyData: Data
        do {
            let recipients = try await fetchRecipientAccountKeysForRoom(
                token: token,
                roomId: roomId,
                senderUserId: senderId
            )

            let encrypted = try MessageCryptoService.shared.encryptMessageForRecipients(
                plaintext: trimmed,
                senderUserId: senderId,
                recipients: recipients
            )

            let request = SendMessageRequest(
                chatRoomId: roomId,
                content: nil,
                contentCiphertext: encrypted.ciphertextBase64,
                encryptedKeys: encrypted.encryptedKeysByUserId,
                clientMessageId: clientMessageId,
                attachmentsInline: nil
            )

            bodyData = try JSONEncoder().encode(request)
        } catch {
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .failed)
            errorText = "Couldn’t send message. You can retry."
            print("❌ sendMessage encryption failed:", error)
            return false
        }

        let job = SendJob(
            clientMessageId: clientMessageId,
            localId: String(localId),
            bodyJSON: bodyData,
            attachmentsMeta: nil
        )

        SendQueueManager.shared.enqueue(job)
        SendQueueManager.shared.startIfNeeded()
        return true
    }

    func sendImageMessage(
        roomId: Int,
        token: String?,
        imageData: Data,
        caption: String? = nil,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        guard !imageData.isEmpty else {
            errorText = "Image data is empty."
            return false
        }

        let sender = SenderDTO(
            id: senderId,
            username: senderUsername,
            publicKey: senderPublicKey,
            avatarUrl: nil
        )

        errorText = nil
        stopTypingNow(roomId: roomId)
        isSendingImage = true
        defer { isSendingImage = false }

        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil

        let clientMessageId = UUID().uuidString
        let localId = -abs(clientMessageId.hashValue)

        do {
            print("🧪 sendImageMessage: starting upload")

            let upload = try await UploadService.shared.uploadImage(data: imageData, token: token)
            print("🧪 sendImageMessage: upload success url =", upload.url)

            let attachment = AttachmentDTO(
                id: nil,
                kind: "IMAGE",
                url: upload.url,
                mimeType: upload.contentType ?? "image/jpeg",
                width: nil,
                height: nil,
                durationSec: nil,
                caption: finalCaption,
                thumbUrl: upload.url
            )

            let optimistic = MessageDTO.optimistic(
                roomId: roomId,
                clientMessageId: clientMessageId,
                localId: localId,
                text: finalCaption,
                attachments: [attachment],
                imageUrl: upload.url,
                senderId: sender.id,
                senderUsername: sender.username,
                senderPublicKey: sender.publicKey
            )

            applyToStore(optimistic)
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .sending)
            refreshFromMessageStore()

            let plaintextForEncryption = finalCaption ?? "[image]"
            print("🧪 sendImageMessage: fetching recipient keys")

            let recipients = try await fetchRecipientAccountKeysForRoom(
                token: token,
                roomId: roomId,
                senderUserId: senderId
            )

            print("🧪 sendImageMessage: encrypting placeholder/caption for recipients")

            let encrypted = try MessageCryptoService.shared.encryptMessageForRecipients(
                plaintext: plaintextForEncryption,
                senderUserId: senderId,
                recipients: recipients
            )

            let bodyRequest = SendMessageRequest(
                chatRoomId: roomId,
                content: nil,
                contentCiphertext: encrypted.ciphertextBase64,
                encryptedKeys: encrypted.encryptedKeysByUserId,
                clientMessageId: clientMessageId,
                attachmentsInline: [attachment]
            )

            let bodyData = try JSONEncoder().encode(bodyRequest)
            print("🧪 sendImageMessage: request encoded, enqueueing")

            let job = SendJob(
                clientMessageId: clientMessageId,
                localId: String(localId),
                bodyJSON: bodyData,
                attachmentsMeta: nil
            )

            SendQueueManager.shared.enqueue(job)
            SendQueueManager.shared.startIfNeeded()
            print("✅ sendImageMessage: queued successfully")
            return true

        } catch {
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .failed)
            errorText = "Couldn’t send image. \(error.localizedDescription)"
            print("❌ sendImageMessage failed:", error)
            return false
        }
    }

    func startSocket(roomId: Int, token: String?, myUsername: String?) {
        guard roomId > 0 else {
            print("❌ startSocket called with invalid roomId:", roomId)
            return
        }

        guard activeRoomId != roomId else { return }

        configureRoom(roomId: roomId)
        stopSocket()

        activeRoomId = roomId

        if let token {
            print("➡️ startSocket: connecting room=\(roomId) tokenPresent=\(!token.isEmpty) tokenPreview=\(token.prefix(8))")
            SocketManager.shared.connect(token: token)
        } else {
            print("❌ startSocket: token missing — skipping connect")
        }

        SocketManager.shared.joinRoom(roomId: roomId)

        startTypingPruneLoop()
        startExpiryLoop()

        if let id = SocketManager.shared.on("message:upsert", callback: { [weak self] data, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleIncomingMessageEvent(data: data, roomId: roomId)
            }
        }) {
            socketListenerIDs.append(id)
        }

        if let id = SocketManager.shared.on("message:expired", callback: { [weak self] data, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleIncomingMessageEvent(data: data, roomId: roomId)
            }
        }) {
            socketListenerIDs.append(id)
        }

        let typingEvents: [(String, Bool)] = [
            ("user_typing", true),
            ("user_stopped_typing", false),
            ("typing:update", true)
        ]

        for (event, defaultTyping) in typingEvents {
            if let id = SocketManager.shared.on(event, callback: { [weak self] data, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleTypingEvent(data: data, roomId: roomId, defaultIsTyping: defaultTyping)
                }
            }) {
                socketListenerIDs.append(id)
            }
        }
    }

    func stopSocket() {
        if let roomId = activeRoomId { SocketManager.shared.leaveRoom(roomId: roomId) }
        for id in socketListenerIDs { SocketManager.shared.off(id) }
        socketListenerIDs.removeAll()
        activeRoomId = nil

        batchSortDebouncer.flush()

        stopTypingPruneLoop()
        stopExpiryLoop()

        typingUsernames.removeAll()
        typingLastSeen.removeAll()
        hasSentTypingStart = false
        typingStopTask?.cancel()
        typingStopTask = nil
    }

    private func handleIncomingMessageEvent(data: [Any], roomId: Int) {
        guard let first = data.first else { return }

        if let dict = first as? [String: Any] {
            let msgDict = (dict["item"] as? [String: Any]) ?? dict
            if let msg: MessageDTO = decodeFromDictionary(msgDict), msg.chatRoomId == roomId {
                applyToStore(msg)
                bumpLastServerIdIfNeeded(msg)
                refreshFromMessageStore()
                markVisibleMessagesRead()
            }
            return
        }

        if let str = first as? String,
           let msg: MessageDTO = decodeFromJSONString(str),
           msg.chatRoomId == roomId {
            applyToStore(msg)
            bumpLastServerIdIfNeeded(msg)
            refreshFromMessageStore()
            markVisibleMessagesRead()
            return
        }
    }

    private func handleTypingEvent(data: [Any], roomId: Int, defaultIsTyping: Bool) {
        guard let first = data.first as? [String: Any] else { return }
        if let rid = first["roomId"] as? Int, rid != roomId { return }

        let username = (first["username"] as? String) ?? (first["name"] as? String) ?? ""
        let isTyping = (first["isTyping"] as? Bool) ?? defaultIsTyping
        applyTypingUpdate(username: username, isTyping: isTyping)
    }

    private func handleMessageEditedEvent(_ payload: [String: Any]) {
        guard let messageId = payload["messageId"] as? Int else { return }

        guard let existing = MessageStore.shared.message(withId: messageId) else { return }
        guard existing.chatRoomId == roomId else { return }

        let rawContent = payload["rawContent"] as? String

        var editedAtDate: Date? = nil
        if let editedAtString = payload["editedAt"] as? String {
            editedAtDate = tolerantISODate(from: editedAtString)
        }

        let patched = MessageDTO(
            id: existing.id,
            contentCiphertext: existing.contentCiphertext,
            rawContent: rawContent ?? existing.rawContent,
            translations: existing.translations,
            translatedFrom: existing.translatedFrom,
            translatedForMe: existing.translatedForMe,
            encryptedKeyForMe: existing.encryptedKeyForMe,
            imageUrl: existing.imageUrl,
            audioUrl: existing.audioUrl,
            audioDurationSec: existing.audioDurationSec,
            attachments: existing.attachments,
            isExplicit: existing.isExplicit,
            createdAt: existing.createdAt,
            expiresAt: existing.expiresAt,
            editedAt: editedAtDate ?? existing.editedAt ?? Date(),
            deletedBySender: existing.deletedBySender,
            deletedForAll: existing.deletedForAll,
            deletedAt: existing.deletedAt,
            deletedById: existing.deletedById,
            sender: existing.sender,
            readBy: existing.readBy,
            chatRoomId: existing.chatRoomId,
            reactionSummary: existing.reactionSummary,
            myReactions: existing.myReactions,
            revision: max((existing.revision ?? 1) + 1, existing.revision ?? 1),
            clientMessageId: existing.clientMessageId
        )

        applyToStore(patched)
        refreshFromMessageStore()
    }

    private func handleMessageDeletedEvent(_ payload: [String: Any]) {
        guard let messageId = payload["messageId"] as? Int else { return }

        let scope = (payload["scope"] as? String)?.lowercased() ?? "me"
        let payloadRoomId = payload["chatRoomId"] as? Int

        if let payloadRoomId, payloadRoomId != roomId {
            return
        }

        guard let existing = MessageStore.shared.message(withId: messageId) else { return }
        guard existing.chatRoomId == roomId else { return }

        if scope == "me" {
            if let userId = payload["userId"] as? Int,
               let currentUserId,
               userId == currentUserId {
                MessageStore.shared.removeMessage(id: messageId)
                refreshFromMessageStore()
            }
            return
        }

        let deletedAtDate: Date? = {
            if let deletedAtString = payload["deletedAt"] as? String {
                return tolerantISODate(from: deletedAtString)
            }
            return nil
        }()

        let deletedById = payload["deletedById"] as? Int

        let patched = MessageDTO(
            id: existing.id,
            contentCiphertext: nil,
            rawContent: nil,
            translations: existing.translations,
            translatedFrom: existing.translatedFrom,
            translatedForMe: nil,
            encryptedKeyForMe: existing.encryptedKeyForMe,
            imageUrl: nil,
            audioUrl: nil,
            audioDurationSec: nil,
            attachments: [],
            isExplicit: existing.isExplicit,
            createdAt: existing.createdAt,
            expiresAt: existing.expiresAt,
            editedAt: existing.editedAt,
            deletedBySender: existing.deletedBySender,
            deletedForAll: true,
            deletedAt: deletedAtDate ?? existing.deletedAt ?? Date(),
            deletedById: deletedById ?? existing.deletedById,
            sender: existing.sender,
            readBy: existing.readBy,
            chatRoomId: existing.chatRoomId,
            reactionSummary: existing.reactionSummary,
            myReactions: existing.myReactions,
            revision: max((existing.revision ?? 1) + 1, existing.revision ?? 1),
            clientMessageId: existing.clientMessageId
        )

        applyToStore(patched)
        refreshFromMessageStore()
    }

    func configureRoom(roomId: Int) {
        guard self.roomId != roomId else { return }
        self.roomId = roomId
        self.lastServerMessageId = loadLastServerMessageId(roomId: roomId)
        refreshFromMessageStore()
        markVisibleMessagesRead()
    }

    func resyncIfNeeded(token: String?) async {
        errorText = nil

        guard let token else {
            self.errorText = "Missing auth token."
            return
        }
        guard let roomId = self.roomId, roomId > 0 else { return }
        guard !isResyncing else { return }

        isResyncing = true
        defer { isResyncing = false }

        SocketManager.shared.joinRoom(roomId: roomId)

        do {
            let path = "messages/\(roomId)/deltas?sinceId=\(lastServerMessageId)"
            print("➡️ resyncIfNeeded path: \(path)")

            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )

            print("✅ resyncIfNeeded success: items=\(page.items.count), nextCursor=\(page.nextCursor ?? "nil"), nextCursorId=\(page.nextCursorId.map(String.init) ?? "nil")")

            errorText = nil

            for msg in page.items {
                bumpLastServerIdIfNeeded(msg)
            }

            applyToStore(page.items)
            batchSortDebouncer.flush()
            refreshFromMessageStore()
            markVisibleMessagesRead()
        } catch {
            errorText = "resyncIfNeeded: \(error.localizedDescription)"
            print("❌ resyncIfNeeded error for roomId \(roomId):", error)
        }
    }

    private func bumpLastServerIdIfNeeded(_ msg: MessageDTO) {
        if msg.id > 0 {
            lastServerMessageId = max(lastServerMessageId, msg.id)
        }
    }

    private func keyForLastId(_ roomId: Int) -> String { "chat.lastServerMessageId.\(roomId)" }

    private func loadLastServerMessageId(roomId: Int) -> Int {
        UserDefaults.standard.integer(forKey: keyForLastId(roomId))
    }

    private func persistLastServerMessageId(_ id: Int, roomId: Int) {
        UserDefaults.standard.set(id, forKey: keyForLastId(roomId))
    }

    private func bestPlaintext(for msg: MessageDTO) -> String {
        if let translated = msg.translatedForMe, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }
        if let raw = msg.rawContent, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return ""
    }

    private func isoString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    func submitReport(
        targetMessage: MessageDTO,
        roomId: Int,
        reason: ReportReason,
        details: String,
        contextCount: Int,
        blockAfterReport: Bool,
        token: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            reportErrorText = "Missing auth token."
            return false
        }

        reportErrorText = nil
        isSubmittingReport = true
        defer { isSubmittingReport = false }

        guard let targetIndex = messages.firstIndex(where: { $0.id == targetMessage.id }) else {
            reportErrorText = "Could not find the selected message."
            return false
        }

        let startIndex = max(0, targetIndex - max(0, contextCount))
        let contextMessages = Array(messages[startIndex...targetIndex])

        let evidence = contextMessages.map { msg in
            ReportEvidenceMessage(
                messageId: msg.id,
                senderId: msg.sender.id,
                createdAt: isoString(msg.createdAt),
                plaintext: bestPlaintext(for: msg),
                translatedForMe: msg.translatedForMe,
                rawContent: msg.rawContent,
                content: nil,
                contentCiphertext: msg.contentCiphertext,
                encryptedKeyForMe: msg.encryptedKeyForMe,
                attachments: (msg.attachments ?? []).map {
                    ReportAttachmentPayload(
                        id: $0.id,
                        kind: $0.kind,
                        url: $0.url,
                        mimeType: $0.mimeType,
                        width: $0.width,
                        height: $0.height,
                        durationSec: $0.durationSec,
                        caption: $0.caption,
                        thumbUrl: $0.thumbUrl
                    )
                },
                deletedForAll: msg.deletedForAll ?? false,
                editedAt: isoString(msg.editedAt)
            )
        }

        let payload = ReportMessageRequest(
            messageId: targetMessage.id,
            chatRoomId: roomId,
            reportedUserId: targetMessage.sender.id,
            reason: reason.rawValue,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            blockAfterReport: blockAfterReport,
            messages: evidence,
            clientMetadata: ReportClientMetadata(
                platform: "ios",
                locale: Locale.current.identifier
            )
        )

        do {
            _ = try await ReportService.shared.submitReport(payload, token: token)

            if blockAfterReport {
                let blockBody = try JSONEncoder().encode(
                    BlockUserRequest(targetUserId: targetMessage.sender.id)
                )

                let _: JSONValue? = try? await APIClient.shared.send(
                    APIRequest(
                        path: "blocks",
                        method: .POST,
                        body: blockBody,
                        requiresAuth: true
                    ),
                    token: token
                )
            }

            return true
        } catch {
            reportErrorText = "Failed to submit report."
            return false
        }
    }

    func handleInputChanged(roomId: Int) {
        guard SocketManager.shared.isConnected else {
            print("⚠️ skipped typing:start (socket not connected)")
            hasSentTypingStart = false
            typingStopTask?.cancel()
            typingStopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self = self else { return }
                self.hasSentTypingStart = false
            }
            return
        }

        if !hasSentTypingStart {
            hasSentTypingStart = true
            SocketManager.shared.emit("typing:start", ["roomId": roomId])
        }

        typingStopTask?.cancel()
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self = self else { return }
            self.hasSentTypingStart = false
            if SocketManager.shared.isConnected {
                SocketManager.shared.emit("typing:stop", ["roomId": roomId])
            }
        }
    }

    func stopTypingNow(roomId: Int) {
        typingStopTask?.cancel()
        typingStopTask = nil

        if hasSentTypingStart {
            hasSentTypingStart = false
            if SocketManager.shared.isConnected {
                SocketManager.shared.emit("typing:stop", ["roomId": roomId])
            } else {
                print("⚠️ skipped typing:stop (socket not connected)")
            }
        }
    }

    func editMessage(
        messageId: Int,
        newText: String,
        token: String?
    ) async -> Bool {
        guard messageId > 0 else {
            errorText = "Only sent messages can be edited."
            return false
        }

        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = "Message cannot be empty."
            return false
        }

        struct EditMessageRequest: Encodable {
            let newContent: String
        }

        struct EditMessageResponse: Decodable {
            let id: Int
            let chatRoomId: Int?
            let rawContent: String?
            let editedAt: Date?
        }

        do {
            let body = try JSONEncoder().encode(EditMessageRequest(newContent: trimmed))

            let updated: EditMessageResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "messages/\(messageId)",
                    method: .PATCH,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )

            guard let existing = MessageStore.shared.message(withId: updated.id) else {
                let patched = MessageDTO(
                    id: updated.id,
                    contentCiphertext: nil,
                    rawContent: updated.rawContent ?? trimmed,
                    translations: nil,
                    translatedFrom: nil,
                    translatedForMe: updated.rawContent ?? trimmed,
                    encryptedKeyForMe: nil,
                    imageUrl: nil,
                    audioUrl: nil,
                    audioDurationSec: nil,
                    attachments: nil,
                    isExplicit: nil,
                    createdAt: Date(),
                    expiresAt: nil,
                    editedAt: updated.editedAt ?? Date(),
                    deletedBySender: nil,
                    deletedForAll: nil,
                    deletedAt: nil,
                    deletedById: nil,
                    sender: currentUserSenderDTO ?? SenderDTO(id: currentUserId ?? 0, username: currentUsername, publicKey: currentUserPublicKey, avatarUrl: nil),
                    readBy: nil,
                    chatRoomId: updated.chatRoomId ?? roomId,
                    reactionSummary: nil,
                    myReactions: nil,
                    revision: 1,
                    clientMessageId: nil
                )

                MessageStore.shared.insertOrReplaceSync([patched])
                DecryptedMessageTextStore.shared.setText(updated.rawContent ?? trimmed, for: patched.id)
                refreshFromMessageStore()
                errorText = nil
                return true
            }

            let patched = MessageDTO(
                id: existing.id,
                contentCiphertext: nil,
                rawContent: updated.rawContent ?? trimmed,
                translations: nil,
                translatedFrom: existing.translatedFrom,
                translatedForMe: updated.rawContent ?? trimmed,
                encryptedKeyForMe: nil,
                imageUrl: existing.imageUrl,
                audioUrl: existing.audioUrl,
                audioDurationSec: existing.audioDurationSec,
                attachments: existing.attachments,
                isExplicit: existing.isExplicit,
                createdAt: existing.createdAt,
                expiresAt: existing.expiresAt,
                editedAt: updated.editedAt ?? Date(),
                deletedBySender: existing.deletedBySender,
                deletedForAll: existing.deletedForAll,
                deletedAt: existing.deletedAt,
                deletedById: existing.deletedById,
                sender: existing.sender,
                readBy: existing.readBy,
                chatRoomId: existing.chatRoomId,
                reactionSummary: existing.reactionSummary,
                myReactions: existing.myReactions,
                revision: max((existing.revision ?? 1) + 1, existing.revision ?? 1),
                clientMessageId: existing.clientMessageId
            )

            MessageStore.shared.insertOrReplaceSync([patched])

            let freshText = updated.rawContent ?? trimmed
            DecryptedMessageTextStore.shared.setText(freshText, for: patched.id)

            refreshFromMessageStore()
            errorText = nil
            return true
        } catch {
            errorText = "Failed to edit message."
            print("❌ editMessage failed:", error)
            return false
        }
    }

    func archiveConversation(
        conversationId: Int,
        kind: String,
        token: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        struct ArchiveRequest: Encodable {
            let archived: Bool
        }

        do {
            let body = try JSONEncoder().encode(ArchiveRequest(archived: true))

            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(kind)/\(conversationId)/archive",
                    method: .PATCH,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )

            errorText = nil
            return true
        } catch {
            errorText = "Failed to archive conversation."
            print("❌ archiveConversation failed:", error)
            return false
        }
    }

    func deleteConversation(
        conversationId: Int,
        kind: String,
        token: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(kind)/\(conversationId)",
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
            )

            errorText = nil
            return true
        } catch {
            errorText = "Failed to delete conversation."
            print("❌ deleteConversation failed:", error)
            return false
        }
    }

    func deleteMessage(
        messageId: Int,
        token: String?,
        deleteForEveryone: Bool = false
    ) async -> Bool {
        if messageId <= 0 {
            MessageStore.shared.removeMessageSync(id: messageId)
            refreshFromMessageStore()
            errorText = nil
            return true
        }

        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        let scope = deleteForEveryone ? "all" : "me"

        do {
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "messages/\(messageId)?scope=\(scope)",
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
            )

            if deleteForEveryone {
                if let existing = MessageStore.shared.message(withId: messageId) {
                    let patched = MessageDTO(
                        id: existing.id,
                        contentCiphertext: nil,
                        rawContent: nil,
                        translations: existing.translations,
                        translatedFrom: existing.translatedFrom,
                        translatedForMe: nil,
                        encryptedKeyForMe: existing.encryptedKeyForMe,
                        imageUrl: nil,
                        audioUrl: nil,
                        audioDurationSec: nil,
                        attachments: [],
                        isExplicit: existing.isExplicit,
                        createdAt: existing.createdAt,
                        expiresAt: existing.expiresAt,
                        editedAt: nil,
                        deletedBySender: existing.deletedBySender,
                        deletedForAll: true,
                        deletedAt: Date(),
                        deletedById: currentUserId,
                        sender: existing.sender,
                        readBy: existing.readBy,
                        chatRoomId: existing.chatRoomId,
                        reactionSummary: existing.reactionSummary,
                        myReactions: existing.myReactions,
                        revision: max((existing.revision ?? 1) + 1, existing.revision ?? 1),
                        clientMessageId: existing.clientMessageId
                    )

                    MessageStore.shared.insertOrReplaceSync([patched])
                }
            } else {
                MessageStore.shared.removeMessageSync(id: messageId)
            }

            await MainActor.run {
                self.refreshFromMessageStore()
                self.errorText = nil
            }
            return true
        } catch {
            errorText = "Failed to delete message."
            print("❌ deleteMessage failed:", error)
            return false
        }
    }

    private func fetchRecipientAccountKeysForRoom(
        token: String,
        roomId: Int,
        senderUserId: Int
    ) async throws -> [RecipientKeyContext] {
        let participantsResponse: RoomParticipantsResponse = try await APIClient.shared.send(
            APIRequest(
                path: "rooms/\(roomId)/participants",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        let recipients = participantsResponse.participants
            .filter { $0.userId != senderUserId }
            .compactMap { participant -> RecipientKeyContext? in
                guard let pk = participant.user?.publicKey,
                      !pk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                return RecipientKeyContext(
                    userId: participant.userId,
                    publicKeyBase64: pk
                )
            }

        guard !recipients.isEmpty else {
            throw NSError(
                domain: "ChatThreadViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No valid recipients with public keys found for this room."]
            )
        }

        return recipients
    }

    private func applyTypingUpdate(username: String, isTyping: Bool) {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if isTyping {
            typingLastSeen[name] = Date()
            if !typingUsernames.contains(name) { typingUsernames.append(name) }
        } else {
            typingLastSeen.removeValue(forKey: name)
            typingUsernames.removeAll { $0 == name }
        }
    }

    private func startTypingPruneLoop() {
        typingPruneTask?.cancel()
        typingPruneTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run { self.pruneTyping() }
            }
        }
    }

    private func stopTypingPruneLoop() {
        typingPruneTask?.cancel()
        typingPruneTask = nil
    }

    private func pruneTyping() {
        let now = Date()
        typingLastSeen = typingLastSeen.filter { now.timeIntervalSince($0.value) < typingTTL }
        typingUsernames = Array(typingLastSeen.keys).sorted()
    }

    private func decodeFromDictionary<T: Decodable>(_ dict: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return nil }
        let decoder = JSONDecoder.tolerantISO8601Decoder()
        return try? decoder.decode(T.self, from: data)
    }

    private func decodeFromJSONString<T: Decodable>(_ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder.tolerantISO8601Decoder()
        return try? decoder.decode(T.self, from: data)
    }

    private func applyToStore(_ incoming: [MessageDTO]) {
        MessageStore.shared.insertOrReplace(incoming)
    }

    private func applyToStore(_ incoming: MessageDTO) {
        MessageStore.shared.insertOrReplace([incoming])
    }

    private func tolerantISODate(from string: String) -> Date? {
        let decoder = JSONDecoder.tolerantISO8601Decoder()
        if let data = "\"\(string)\"".data(using: .utf8) {
            return try? decoder.decode(Date.self, from: data)
        }
        return nil
    }
}
