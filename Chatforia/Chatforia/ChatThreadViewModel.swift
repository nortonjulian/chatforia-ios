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
    let messageField: MessageDTO?

    enum CodingKeys: String, CodingKey {
        case item
        case shaped
        case messageField = "message"
    }

    var message: MessageDTO? { item ?? shaped ?? messageField }
}

struct BlockUserRequest: Encodable {
    let targetUserId: Int
}

struct ReportCreateRequest: Encodable {
    let messageId: Int
    let reason: String
    let details: String?
    let contextCount: Int
    let blockAfterReport: Bool
}

struct ReportCreateResponse: Decodable {
    let success: Bool
}

struct EmptyAPIResponse: Decodable {}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var isLoadingOlder: Bool = false
    @Published var typingUsernames: [String] = []
    @Published var isSendingImage: Bool = false
    @Published var randomSession: RandomSession? = nil
    @Published var isSendingAudio: Bool = false
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
    
    private var pendingReadMessageIds = Set<Int>()
    private var readFlushTask: Task<Void, Never>?

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

        NotificationCenter.default.publisher(for: .socketMessageUpsert)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let payload = note.userInfo?["payload"] as? [String: Any] else { return }
                self.handleSocketUpsert(payload)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .socketMessageExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let payload = note.userInfo?["payload"] as? [String: Any] else { return }
                self.handleSocketUpsert(payload)
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

        NotificationCenter.default.publisher(for: .socketDidReconnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.resyncIfNeeded(token: TokenStore.shared.read())
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .init("randomFriendAccepted"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard let roomId = note.object as? Int else { return }
                guard self.randomSession?.roomId == roomId else { return }

                self.randomSession?.partnerRequestedFriend = true
            }
            .store(in: &cancellables)
    }

    deinit {
        expiryTask?.cancel()
        typingStopTask?.cancel()
        typingPruneTask?.cancel()
        readFlushTask?.cancel()
    }

    func configureRandomSession(roomId: Int, myAlias: String, partnerAlias: String) {
        if let existing = randomSession, existing.roomId == roomId {
            return
        }

        randomSession = RandomSession(
            roomId: roomId,
            myAlias: myAlias,
            partnerAlias: partnerAlias
        )
    }

    func requestAddFriend() async {
        guard let session = randomSession else { return }

        SocketManager.shared.emit("random:add_friend", [
            "roomId": session.roomId
        ])

        randomSession?.iRequestedFriend = true
    }

    func nextPerson() async {
        guard let session = randomSession else { return }

        SocketManager.shared.emit("random:skip", [
            "roomId": session.roomId
        ])

        SocketManager.shared.markRandomMatchCompleted()

        NotificationCenter.default.post(
            name: .init("randomNextPerson"),
            object: nil
        )
    }

    func configureCurrentUser(id: Int?, username: String?, publicKey: String? = nil) {
        self.currentUserId = id
        self.currentUsername = username
        self.currentUserPublicKey = publicKey

        if let id {
            UserDefaults.standard.set(id, forKey: "chatforia.currentUserId")
        }
    }

    private func handleMessageEditedEvent(_ payload: [String: Any]) {
        handleSocketUpsert(payload)
    }

    private func handleMessageDeletedEvent(_ payload: [String: Any]) {
        handleSocketUpsert(payload)
    }

    private func startTypingPruneLoop() {
        guard typingPruneTask == nil else { return }

        typingPruneTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                await MainActor.run {
                    let now = Date()

                    self.typingLastSeen = self.typingLastSeen.filter {
                        now.timeIntervalSince($0.value) < self.typingTTL
                    }
                    self.typingUsernames = self.typingLastSeen.keys.sorted()

                    if self.typingLastSeen.isEmpty {
                        self.typingPruneTask?.cancel()
                        self.typingPruneTask = nil
                    }
                }
            }
        }
    }

    func receivedTyping(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        typingLastSeen[trimmed] = Date()
        typingUsernames = typingLastSeen.keys.sorted()
        startTypingPruneLoop()
    }

    func clearTypingUsers() {
        typingLastSeen.removeAll()
        typingUsernames = []
        typingPruneTask?.cancel()
        typingPruneTask = nil
    }

    private func fetchRecipientAccountKeysForRoom(
        token: String,
        roomId: Int,
        senderUserId: Int
    ) async throws -> [RecipientKeyContext] {
        let response: RoomParticipantsResponse = try await APIClient.shared.send(
            APIRequest(path: "chatrooms/\(roomId)/participants", method: .GET, requiresAuth: true),
            token: token
        )

        let recipients = response.participants.compactMap { participant -> RecipientKeyContext? in
            guard participant.userId != senderUserId else { return nil }
            guard let publicKey = participant.user?.publicKey, !publicKey.isEmpty else { return nil }

            return RecipientKeyContext(
                userId: participant.userId,
                publicKeyBase64: publicKey
            )
        }

        if recipients.isEmpty {
            throw NSError(
                domain: "ChatThreadViewModel",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No recipient public keys found for this room."]
            )
        }

        return recipients
    }

    private func buildEncryptedEditPayload(
        roomId: Int,
        plaintext: String,
        token: String,
        senderUserId: Int
    ) async throws -> EncryptedMessagePayload {
        let recipients = try await fetchRecipientAccountKeysForRoom(
            token: token,
            roomId: roomId,
            senderUserId: senderUserId
        )

        return try MessageCryptoService.shared.encryptMessageForRecipients(
            plaintext: plaintext,
            senderUserId: senderUserId,
            recipients: recipients
        )
    }

    func resyncIfNeeded(token: String?) async {
        guard !isResyncing else { return }
        guard let roomId else { return }
        guard let token, !token.isEmpty else { return }

        isResyncing = true
        defer { isResyncing = false }

        let sinceId = lastServerMessageId
        guard sinceId > 0 else {
            await loadMessages(roomId: roomId, token: token)
            return
        }

        do {
            let path = "messages/\(roomId)/deltas?sinceId=\(sinceId)"
            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )

            guard !page.items.isEmpty else { return }

            applyToStore(page.items)
            batchSortDebouncer.flush()
            refreshFromMessageStore()
            scheduleMarkVisibleMessagesRead()
        } catch {
            print("❌ resyncIfNeeded delta error:", error)
            await loadMessages(roomId: roomId, token: token)
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

        pendingReadMessageIds.formUnion(unread)
        scheduleMarkVisibleMessagesRead()
    }

    private func scheduleMarkVisibleMessagesRead() {
        readFlushTask?.cancel()

        readFlushTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 350_000_000)

            let ids = Array(self.pendingReadMessageIds).sorted()
            guard !ids.isEmpty else { return }

            self.pendingReadMessageIds.removeAll()
            APIClient.shared.readMessagesBulk(ids)
        }
    }

    func startExpiryLoop() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            guard let self else { return }
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

            MessageStore.shared.removeMessages(forRoomId: roomId)
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
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let sender = SenderDTO(
            id: senderId,
            username: senderUsername,
            publicKey: senderPublicKey,
            avatarUrl: nil
        )

        errorText = nil
        stopTypingNow(roomId: roomId)

        let clientMessageId = UUID().uuidString
        let localId = -abs(clientMessageId.hashValue)

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
            MessageStore.shared.setDeliveryState(
                clientMessageId: clientMessageId,
                state: .sending
            )
            refreshFromMessageStore()

            let bodyRequest = SendMessageRequest(
                chatRoomId: roomId,
                content: nil,
                contentCiphertext: encrypted.ciphertextBase64,
                encryptedKeys: encrypted.encryptedKeysByUserId,
                clientMessageId: clientMessageId,
                attachmentsInline: nil
            )

            let bodyData = try JSONEncoder().encode(bodyRequest)

            let job = SendJob(
                clientMessageId: clientMessageId,
                localId: String(localId),
                bodyJSON: bodyData,
                attachmentsMeta: nil
            )

            SendQueueManager.shared.enqueue(job)
            SendQueueManager.shared.startIfNeeded()
            return true
        } catch {
            MessageStore.shared.setDeliveryState(
                clientMessageId: clientMessageId,
                state: .failed
            )
            errorText = "Couldn’t send message. \(error.localizedDescription)"
            return false
        }
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
            let upload = try await UploadService.shared.uploadImage(data: imageData, token: token)

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

            let recipients = try await fetchRecipientAccountKeysForRoom(
                token: token,
                roomId: roomId,
                senderUserId: senderId
            )

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

            let job = SendJob(
                clientMessageId: clientMessageId,
                localId: String(localId),
                bodyJSON: bodyData,
                attachmentsMeta: nil
            )

            SendQueueManager.shared.enqueue(job)
            SendQueueManager.shared.startIfNeeded()
            return true
        } catch {
            MessageStore.shared.setDeliveryState(
                clientMessageId: clientMessageId,
                state: .failed
            )
            errorText = "Couldn’t send image. \(error.localizedDescription)"
            return false
        }
    }

    func sendGIFMessage(
        roomId: Int,
        token: String?,
        gifData: Data,
        caption: String? = nil,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        guard !gifData.isEmpty else {
            errorText = "GIF data is empty."
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

        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil

        let clientMessageId = UUID().uuidString
        let localId = -abs(clientMessageId.hashValue)

        do {
            let upload = try await UploadService.shared.uploadGIF(data: gifData, token: token)

            let attachment = AttachmentDTO(
                id: nil,
                kind: "GIF",
                url: upload.url,
                mimeType: upload.contentType ?? "image/gif",
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
                imageUrl: nil,
                senderId: sender.id,
                senderUsername: sender.username,
                senderPublicKey: sender.publicKey
            )

            applyToStore(optimistic)
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .sending)
            refreshFromMessageStore()

            let plaintextForEncryption = finalCaption ?? "[gif]"

            let recipients = try await fetchRecipientAccountKeysForRoom(
                token: token,
                roomId: roomId,
                senderUserId: senderId
            )

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

            let job = SendJob(
                clientMessageId: clientMessageId,
                localId: String(localId),
                bodyJSON: bodyData,
                attachmentsMeta: nil
            )

            SendQueueManager.shared.enqueue(job)
            SendQueueManager.shared.startIfNeeded()
            return true
        } catch {
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .failed)
            errorText = "Couldn’t send GIF. \(error.localizedDescription)"
            return false
        }
    }

    func sendAudioMessage(
        roomId: Int,
        token: String?,
        fileURL: URL,
        durationSec: Double,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
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
        isSendingAudio = true
        defer { isSendingAudio = false }

        let clientMessageId = UUID().uuidString
        let localId = -abs(clientMessageId.hashValue)

        do {
            let upload = try await UploadService.shared.uploadAudio(fileURL: fileURL, token: token)

            let attachment = AttachmentDTO(
                id: nil,
                kind: "AUDIO",
                url: upload.url,
                mimeType: upload.contentType ?? "audio/m4a",
                width: nil,
                height: nil,
                durationSec: durationSec,
                caption: nil,
                thumbUrl: nil
            )

            let optimistic = MessageDTO.optimistic(
                roomId: roomId,
                clientMessageId: clientMessageId,
                localId: localId,
                text: nil,
                attachments: [attachment],
                imageUrl: nil,
                audioUrl: upload.url,
                audioDurationSec: durationSec,
                senderId: sender.id,
                senderUsername: sender.username,
                senderPublicKey: sender.publicKey
            )

            applyToStore(optimistic)
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .sending)
            refreshFromMessageStore()

            let recipients = try await fetchRecipientAccountKeysForRoom(
                token: token,
                roomId: roomId,
                senderUserId: senderId
            )

            let encrypted = try MessageCryptoService.shared.encryptMessageForRecipients(
                plaintext: "[voice note]",
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

            let job = SendJob(
                clientMessageId: clientMessageId,
                localId: String(localId),
                bodyJSON: bodyData,
                attachmentsMeta: nil
            )

            SendQueueManager.shared.enqueue(job)
            SendQueueManager.shared.startIfNeeded()
            return true
        } catch {
            MessageStore.shared.setDeliveryState(
                clientMessageId: clientMessageId,
                state: .failed
            )
            errorText = "Couldn’t send audio. \(error.localizedDescription)"
            return false
        }
    }

    func typingStarted(roomId: Int) {
        guard SocketManager.shared.isConnected else {
            print("⚠️ [Socket] typingStarted skipped - not connected yet (room \(roomId))")
            return
        }

        guard !hasSentTypingStart else {
            scheduleTypingStop(roomId: roomId)
            return
        }

        hasSentTypingStart = true
        SocketManager.shared.emit("typing:start", ["roomId": roomId])
        scheduleTypingStop(roomId: roomId)
    }

    func stopTypingNow(roomId: Int) {
        typingStopTask?.cancel()
        typingStopTask = nil

        guard hasSentTypingStart else { return }
        hasSentTypingStart = false

        SocketManager.shared.emit("typing:stop", ["roomId": roomId])
    }

    private func scheduleTypingStop(roomId: Int) {
        typingStopTask?.cancel()
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self?.stopTypingNow(roomId: roomId)
            }
        }
    }

    private func configureRoom(roomId: Int) {
        self.roomId = roomId
        self.activeRoomId = roomId
        self.lastServerMessageId = readPersistedLastServerMessageId(roomId: roomId)
        refreshFromMessageStore()
        startTypingPruneLoop()
    }

    private func applyToStore(_ message: MessageDTO) {
        MessageStore.shared.upsertMessage(message)

        if message.chatRoomId == roomId, message.id > lastServerMessageId {
            lastServerMessageId = message.id
        }
    }

    private func applyToStore(_ newMessages: [MessageDTO]) {
        guard !newMessages.isEmpty else { return }

        for message in newMessages {
            MessageStore.shared.upsertMessage(message)

            if message.chatRoomId == roomId, message.id > lastServerMessageId {
                lastServerMessageId = message.id
            }
        }
    }

    private func persistLastServerMessageId(_ id: Int, roomId: Int) {
        UserDefaults.standard.set(id, forKey: lastServerMessageIdDefaultsKey(roomId: roomId))
    }

    private func readPersistedLastServerMessageId(roomId: Int) -> Int {
        UserDefaults.standard.integer(forKey: lastServerMessageIdDefaultsKey(roomId: roomId))
    }

    private func lastServerMessageIdDefaultsKey(roomId: Int) -> String {
        "chatforia.lastServerMessageId.\(roomId)"
    }

    @MainActor
    private func handleSocketUpsert(_ payload: [String: Any]) {
        print("📨 [Socket] handleSocketUpsert - payload keys: \(Array(payload.keys))")

        guard let configuredRoomId = roomId else {
            print("⚠️ [Socket] no active roomId")
            return
        }

        var messageDict: [String: Any] = payload
        if let item = payload["item"] as? [String: Any] {
            messageDict = item
        } else if let shaped = payload["shaped"] as? [String: Any] {
            messageDict = shaped
        } else if let msg = payload["message"] as? [String: Any] {
            messageDict = msg
        }

        guard let incoming = decodeMessageDTOFromJSONObject(messageDict) else {
            print("❌ [Socket] Failed to decode incoming message")
            print("Payload was:", messageDict)
            return
        }

        guard incoming.chatRoomId == configuredRoomId else {
            print("⚠️ [Socket] room mismatch: \(incoming.chatRoomId ?? -1) vs \(configuredRoomId)")
            return
        }

        print("✅ [Socket] decoded message id=\(incoming.id), clientMessageId=\(incoming.clientMessageId ?? "nil")")

        let incomingId = incoming.id

        if incomingId > 0 {
            if let index = messages.firstIndex(where: { $0.id == incomingId }) {
                messages[index] = MessageDTO.merged(current: messages[index], incoming: incoming)
                print("🔄 [Socket] Updated existing message id=\(incomingId)")
            } else if let clientId = incoming.clientMessageId,
                      let index = messages.firstIndex(where: { $0.clientMessageId == clientId }) {
                messages[index] = MessageDTO.merged(current: messages[index], incoming: incoming)
                print("✅ [Socket] Replaced optimistic message with real id=\(incomingId)")
            } else {
                messages.append(incoming)
                print("🆕 [Socket] Added new message id=\(incomingId)")
            }
        } else {
            messages.append(incoming)
            print("🆕 [Socket] Added new message (no id)")
        }

        messages.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }

        applyToStore(incoming)
        scheduleMarkVisibleMessagesRead()
    }

    private func decodeMessageDTO(from payload: [String: Any]) -> MessageDTO? {
        if let nested = payload["item"] as? [String: Any] {
            return decodeMessageDTOFromJSONObject(nested)
        }

        if let nested = payload["message"] as? [String: Any] {
            return decodeMessageDTOFromJSONObject(nested)
        }

        if let nested = payload["shaped"] as? [String: Any] {
            return decodeMessageDTOFromJSONObject(nested)
        }

        return decodeMessageDTOFromJSONObject(payload)
    }

    private func decodeMessageDTOFromJSONObject(_ object: [String: Any]) -> MessageDTO? {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [])

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()

                if let string = try? container.decode(String.self) {
                    let formatterWithFractional = ISO8601DateFormatter()
                    formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                    let formatterPlain = ISO8601DateFormatter()
                    formatterPlain.formatOptions = [.withInternetDateTime]

                    if let date = formatterWithFractional.date(from: string) ??
                        formatterPlain.date(from: string) {
                        return date
                    }

                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid ISO8601 date string: \(string)"
                    )
                }

                if let seconds = try? container.decode(Double.self) {
                    return Date(timeIntervalSince1970: seconds)
                }

                if let millis = try? container.decode(Int64.self) {
                    return Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
                }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported date format"
                )
            }

            return try decoder.decode(MessageDTO.self, from: data)
        } catch {
            print("❌ Failed to decode MessageDTO from socket payload:", error)
            print("❌ Payload object:", object)
            return nil
        }
    }
}

extension ChatThreadViewModel {
    func startSocket(roomId: Int, token: String?, myUsername: String?) {
        _ = myUsername
        guard let token, !token.isEmpty else { return }

        Task { @MainActor in
            do {
                try await SocketManager.shared.connectAsync(token: token, timeoutSecs: 12)
                SocketManager.shared.joinRoom(roomId)
                print("✅ [Socket] startSocket succeeded - connected + joined room \(roomId)")
            } catch {
                print("❌ [Socket] startSocket failed for room \(roomId):", error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                SocketManager.shared.connect(token: token)
                SocketManager.shared.joinRoom(roomId)
            }
        }
    }

    func stopSocket(roomId: Int) {
        SocketManager.shared.leaveRoom(roomId)
        clearTypingUsers()
    }

    func handleInputChanged(roomId: Int) {
        typingStarted(roomId: roomId)
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
        _ = roomId

        guard let token, !token.isEmpty else {
            reportErrorText = "Missing auth token."
            return false
        }

        isSubmittingReport = true
        reportErrorText = nil
        defer { isSubmittingReport = false }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = ReportCreateRequest(
            messageId: targetMessage.id,
            reason: reason.rawValue,
            details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            contextCount: contextCount,
            blockAfterReport: blockAfterReport
        )

        do {
            let bodyData = try JSONEncoder().encode(payload)

            let _: ReportCreateResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "reports/messages",
                    method: .POST,
                    body: bodyData,
                    requiresAuth: true
                ),
                token: token
            )

            return true
        } catch {
            reportErrorText = error.localizedDescription
            return false
        }
    }

    func editMessage(
        message: MessageDTO,
        newText: String,
        token: String?
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            let body: [String: Any]
            let isEncrypted = (message.contentCiphertext?.isEmpty == false) || (message.encryptedKeyForMe?.isEmpty == false)

            if isEncrypted {
                guard let roomId = message.chatRoomId else {
                    errorText = "Missing room id."
                    return false
                }

                let encrypted = try await buildEncryptedEditPayload(
                    roomId: roomId,
                    plaintext: trimmed,
                    token: token,
                    senderUserId: message.sender.id
                )

                body = [
                    "contentCiphertext": encrypted.ciphertextBase64,
                    "encryptedKeys": encrypted.encryptedKeysByUserId
                ]
            } else {
                body = [
                    "content": trimmed
                ]
            }

            let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])

            let envelope: MessageEnvelope = try await APIClient.shared.send(
                APIRequest(
                    path: "messages/\(message.id)/edit",
                    method: .PATCH,
                    body: bodyData,
                    requiresAuth: true
                ),
                token: token
            )

            guard let updated = envelope.message else {
                errorText = "Couldn't edit message."
                return false
            }

            applyToStore(updated)
            refreshFromMessageStore()
            return true
        } catch {
            errorText = "Couldn't edit message."
            return false
        }
    }

    func deleteMessage(
        messageId: Int,
        token: String?,
        deleteForEveryone: Bool
    ) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        if messageId <= 0 {
            return true
        }

        do {
            let path = deleteForEveryone
                ? "messages/\(messageId)?scope=all"
                : "messages/\(messageId)?scope=me"

            let _: EmptyAPIResponse = try await APIClient.shared.send(
                APIRequest(
                    path: path,
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
            )

            if !deleteForEveryone {
                MessageStore.shared.removeMessage(id: messageId)
                self.messages.removeAll { $0.id == messageId }
            } else {
                refreshFromMessageStore()
            }

            return true
        } catch {
            errorText = "Couldn’t delete message."
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

        struct ArchiveConversationRequest: Encodable {
            let archived: Bool
        }

        do {
            let bodyData = try JSONEncoder().encode(
                ArchiveConversationRequest(archived: true)
            )

            let path: String
            if kind == "chat" {
                path = "chatrooms/\(conversationId)/archive"
            } else {
                path = "conversations/\(conversationId)/archive"
            }

            let _: EmptyAPIResponse = try await APIClient.shared.send(
                APIRequest(
                    path: path,
                    method: .PATCH,
                    body: bodyData,
                    requiresAuth: true
                ),
                token: token
            )

            return true
        } catch {
            errorText = "Couldn’t archive conversation."
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

        let path: String
        if kind == "chat" {
            path = "chatrooms/\(conversationId)"
        } else {
            path = "conversations/\(conversationId)"
        }

        do {
            let _: EmptyAPIResponse = try await APIClient.shared.send(
                APIRequest(
                    path: path,
                    method: .DELETE,
                    requiresAuth: true
                ),
                token: token
            )

            return true
        } catch {
            errorText = "Couldn’t delete conversation."
            return false
        }
    }
}
