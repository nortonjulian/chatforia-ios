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
}

struct MessageEnvelope: Decodable {
    let item: MessageDTO?

    let shaped: MessageDTO?

    var message: MessageDTO? { item ?? shaped }
}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var isLoadingOlder: Bool = false
    @Published var typingUsernames: [String] = []

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

    // MARK: - Expiry Loop

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

    // MARK: - Networking

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

    func sendMessage(roomId: Int, token: String?, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return
        }

        errorText = nil
        stopTypingNow(roomId: roomId)

        let clientMessageId = UUID().uuidString
        let localId = -abs(clientMessageId.hashValue)

        guard let sender = currentUserSenderDTO else {
            errorText = "Missing current user identity for optimistic send."
            print("❌ sendMessage: current user identity not configured")
            return
        }

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
            let recipientContext = try await fetchRecipientAccountKeyForDirectChat(
                token: token,
                roomId: roomId
            )

            guard let senderUserId = currentUserId else {
                throw NSError(
                    domain: "ChatThreadViewModel",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing current user id"]
                )
            }

            let encrypted = try MessageCryptoService.shared.encryptMessageForCurrentBackend(
                plaintext: trimmed,
                senderUserId: senderUserId,
                recipientUserId: recipientContext.recipientUserId,
                recipientPublicKeyBase64: recipientContext.recipientPublicKey
            )

            let request = SendMessageRequest(
                chatRoomId: roomId,
                content: nil,
                contentCiphertext: encrypted.ciphertextBase64,
                encryptedKeys: encrypted.encryptedKeysByUserId,
                clientMessageId: clientMessageId
            )

            bodyData = try JSONEncoder().encode(request)
        } catch {
            MessageStore.shared.setDeliveryState(clientMessageId: clientMessageId, state: .failed)
            errorText = "Encryption failed: \(error.localizedDescription)"
            print("❌ sendMessage encryption/build error:", error)
            return
        }
        let job = SendJob(
            clientMessageId: clientMessageId,
            localId: String(localId),
            bodyJSON: bodyData,
            attachmentsMeta: nil
        )

        SendQueueManager.shared.enqueue(job)
        SendQueueManager.shared.startIfNeeded()
    }
    // MARK: - Socket wiring

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

    // MARK: - Socket event handlers

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

    // MARK: - Deterministic resync

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
    private func loadLastServerMessageId(roomId: Int) -> Int { UserDefaults.standard.integer(forKey: keyForLastId(roomId)) }
    private func persistLastServerMessageId(_ id: Int, roomId: Int) { UserDefaults.standard.set(id, forKey: keyForLastId(roomId)) }

    // MARK: - Typing helpers

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
    
    
    private func fetchRecipientAccountKeyForDirectChat(
        token: String,
        roomId: Int
    ) async throws -> (recipientUserId: Int, recipientPublicKey: String) {
        guard let currentUserId else {
            throw NSError(
                domain: "ChatThreadViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing current user id"]
            )
        }

        let participantsResponse: RoomParticipantsResponse = try await APIClient.shared.send(
            APIRequest(
                path: "rooms/\(roomId)/participants",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        print("🧪 participantsResponse =", participantsResponse)

        let otherParticipants = participantsResponse.participants
            .filter { $0.userId != currentUserId }

        guard otherParticipants.count == 1, let recipient = otherParticipants.first else {
            throw NSError(
                domain: "ChatThreadViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This room is not a true 1:1 chat. Expected exactly one recipient."]
            )
        }

        print("🧪 recipient.user?.id =", recipient.user?.id as Any)
        print("🧪 recipient.user?.username =", recipient.user?.username as Any)
        print("🧪 recipient.user?.publicKey =", recipient.user?.publicKey as Any)

        guard let recipientPublicKey = recipient.user?.publicKey,
              !recipientPublicKey.isEmpty else {
            throw MessageCryptoError.invalidRecipientPublicKey
        }

        print("🧪 resolved recipient userId = \(recipient.userId)")
        print("🧪 resolved recipient account public key prefix = \(recipientPublicKey.prefix(24))")

        return (
            recipientUserId: recipient.userId,
            recipientPublicKey: recipientPublicKey
        )
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

    // MARK: - JSON helpers

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
