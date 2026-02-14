import Foundation
import Combine

struct MessagesPageResponse: Decodable {
    let items: [MessageDTO]
    let nextCursor: Int?
    let count: Int
}

struct SendMessageRequest: Encodable {
    let chatRoomId: Int
    let content: String
    let clientMessageId: String
}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    // Typing banner data (render these in UI)
    @Published var typingUsernames: [String] = []

    private var typingStopTask: Task<Void, Never>?
    private var hasSentTypingStart: Bool = false

    private var socketListenerIDs: [UUID] = []
    private var activeRoomId: Int?

    // ✅ Typing auto-expire (never stuck)
    private var typingLastSeen: [String: Date] = [:]
    private var typingPruneTask: Task<Void, Never>?
    private let typingTTL: TimeInterval = 4.0

    // ✅ keep base route consistent with ChatsViewModel
    private let basePath = ChatsViewModel.chatroomsBasePath

    // MARK: - Private helpers (formatters)

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Networking

    func loadMessages(roomId: Int, token: String?) async {
        guard let token else { errorText = "Missing auth token."; return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let path = "messages/\(roomId)" // ✅ canonical

        do {
            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )

            // ✅ Normalize server’s newest-first into oldest-first for UI
            self.messages = []

            for m in page.items {
                insertOrReplace(m)
            }

            if self.messages.isEmpty {
                self.errorText = "Loaded 0 messages for room \(roomId)."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func sendMessage(roomId: Int, token: String?, text: String) async {
        guard let token else { errorText = "Missing auth token."; return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorText = nil
        stopTypingNow(roomId: roomId)

        let clientId = UUID().uuidString
        let localId = -abs(clientId.hashValue)

        let optimistic = MessageDTO(
            id: localId,
            clientMessageId: clientId,
            contentCiphertext: nil,
            rawContent: trimmed,
            translations: nil,
            translatedFrom: nil,
            translatedContent: nil,
            translatedTo: nil,
            translatedForMe: nil,
            isExplicit: nil,
            imageUrl: nil,
            audioUrl: nil,
            audioDurationSec: nil,
            expiresAt: nil,
            deletedBySender: nil,
            deletedAt: nil,
            deletedForAll: nil,
            deletedById: nil,
            senderId: nil,
            sender: nil,
            chatRoomId: roomId,
            randomChatRoomId: nil,
            createdAt: isoFormatter.string(from: Date()), // ✅ optimistic timestamp
            isAutoReply: nil
        )

        insertOrReplace(optimistic)

        do {
            let body = try JSONEncoder().encode(
                SendMessageRequest(chatRoomId: roomId, content: trimmed, clientMessageId: clientId)
            )

            // NOTE: if server returns { item }, change to a wrapper decode and use wrapper.item here
            let saved: MessageDTO = try await APIClient.shared.send(
                APIRequest(path: "messages", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            insertOrReplace(saved)
        } catch {
            // Minimal: remove optimistic bubble on failure
            messages.removeAll { $0.clientMessageId == clientId }
            errorText = error.localizedDescription
        }
    }

    // MARK: - Socket wiring

    /// Call when entering a room. Safe to call multiple times; it will rebind if room changes.
    func startSocket(roomId: Int, token: String?, myUsername: String?) {
        guard activeRoomId != roomId else { return }
        stopSocket() // clean previous room

        activeRoomId = roomId

        if let token {
            SocketManager.shared.connect(token: token)
        }

        // ✅ Start typing auto-expire loop for this room
        SocketManager.shared.joinRoom(roomId: roomId)
        startTypingPruneLoop()

        // message:new
        if let id = SocketManager.shared.on("message:new", callback: { [weak self] data, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleIncomingMessageEvent(data: data, roomId: roomId)
            }
        }) {
            socketListenerIDs.append(id)
        }

        // typing events (support multiple naming conventions)
        let typingEvents: [(String, Bool)] = [
            ("user_typing", true),
            ("user_stopped_typing", false),
            ("typing:update", true) // will read isTyping from payload if present
        ]

        for (event, defaultTyping) in typingEvents {
            if let id = SocketManager.shared.on(event, callback: { [weak self] data, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.handleTypingEvent(data: data, roomId: roomId, defaultIsTyping: defaultTyping)
                }
            }) {
                socketListenerIDs.append(id)
            }
        }
    }

    func stopSocket() {
        if let roomId = activeRoomId {
            SocketManager.shared.leaveRoom(roomId: roomId)
        }
        for id in socketListenerIDs {
            SocketManager.shared.off(id)
        }
        socketListenerIDs.removeAll()
        activeRoomId = nil

        // ✅ Stop typing loop + clear state so nothing “sticks” across rooms
        stopTypingPruneLoop()
        typingUsernames.removeAll()
        typingLastSeen.removeAll()
        hasSentTypingStart = false
        typingStopTask?.cancel()
        typingStopTask = nil
    }

    // MARK: - Typing emits

    func handleInputChanged(roomId: Int) {
        if !hasSentTypingStart {
            hasSentTypingStart = true
            SocketManager.shared.emit("typing:start", ["roomId": roomId])
        }

        typingStopTask?.cancel()
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            self.hasSentTypingStart = false
            SocketManager.shared.emit("typing:stop", ["roomId": roomId])
        }
    }

    func stopTypingNow(roomId: Int) {
        typingStopTask?.cancel()
        typingStopTask = nil

        if hasSentTypingStart {
            hasSentTypingStart = false
            SocketManager.shared.emit("typing:stop", ["roomId": roomId])
        }
    }

    // ✅ Never-stuck typing: updates refresh last-seen; pruning removes stale names
    func applyTypingUpdate(username: String, isTyping: Bool) {
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

    // MARK: - Private helpers (typing auto-expire)

    private func startTypingPruneLoop() {
        typingPruneTask?.cancel()
        typingPruneTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.pruneTyping()
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

    // MARK: - Private helpers (messages reconciliation)

    private func isBlank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Prefer incoming if it’s non-blank; otherwise keep existing.
    private func preferNonBlank(_ incoming: String?, _ existing: String?) -> String? {
        if !isBlank(incoming) { return incoming }
        return existing
    }

    /// Day 2 merge rules:
    /// - server fields win
    /// - never overwrite translated/derived fields with blank
    /// - only accept server ids (>0) over optimistic ids (<0)
    private func mergeMessage(existing: MessageDTO, incoming: MessageDTO) -> MessageDTO {
        MessageDTO(
            id: (incoming.id > 0 ? incoming.id : existing.id),
            clientMessageId: incoming.clientMessageId ?? existing.clientMessageId,
            contentCiphertext: incoming.contentCiphertext ?? existing.contentCiphertext,
            rawContent: preferNonBlank(incoming.rawContent, existing.rawContent),

            translations: incoming.translations ?? existing.translations,
            translatedFrom: incoming.translatedFrom ?? existing.translatedFrom,
            translatedContent: preferNonBlank(incoming.translatedContent, existing.translatedContent),
            translatedTo: incoming.translatedTo ?? existing.translatedTo,
            translatedForMe: preferNonBlank(incoming.translatedForMe, existing.translatedForMe),

            isExplicit: incoming.isExplicit ?? existing.isExplicit,

            imageUrl: incoming.imageUrl ?? existing.imageUrl,
            audioUrl: incoming.audioUrl ?? existing.audioUrl,
            audioDurationSec: incoming.audioDurationSec ?? existing.audioDurationSec,

            expiresAt: incoming.expiresAt ?? existing.expiresAt,

            deletedBySender: incoming.deletedBySender ?? existing.deletedBySender,
            deletedAt: incoming.deletedAt ?? existing.deletedAt,
            deletedForAll: incoming.deletedForAll ?? existing.deletedForAll,
            deletedById: incoming.deletedById ?? existing.deletedById,

            senderId: incoming.senderId ?? existing.senderId,
            sender: incoming.sender ?? existing.sender,

            chatRoomId: incoming.chatRoomId ?? existing.chatRoomId, 
            randomChatRoomId: incoming.randomChatRoomId ?? existing.randomChatRoomId,

            createdAt: incoming.createdAt ?? existing.createdAt,
            isAutoReply: incoming.isAutoReply ?? existing.isAutoReply
        )
    }

    /// Canonical upsert:
    /// 1) match by id (server) first
    /// 2) else match by clientMessageId
    /// 3) else optional fallback by content for legacy payloads
    private func insertOrReplace(_ incoming: MessageDTO) {
        // 1) Match by id first
        if let idx = messages.firstIndex(where: { $0.id == incoming.id }) {
            messages[idx] = mergeMessage(existing: messages[idx], incoming: incoming)
            sortMessagesInPlace()
            return
        }

        // 2) Else match by clientMessageId
        if let cmid = incoming.clientMessageId,
           let idx = messages.firstIndex(where: { $0.clientMessageId == cmid }) {
            messages[idx] = mergeMessage(existing: messages[idx], incoming: incoming)
            sortMessagesInPlace()
            return
        }

        // 3) Fallback reconcile-by-content (optional but ok)
        if incoming.clientMessageId == nil,
           let incomingText = incoming.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !incomingText.isEmpty {

            if let idx = messages.lastIndex(where: { m in
                m.chatRoomId == incoming.chatRoomId &&
                (m.id < 0) && // optimistic local ids are negative
                (m.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines) == incomingText)
            }) {
                messages[idx] = mergeMessage(existing: messages[idx], incoming: incoming)
                sortMessagesInPlace()
                return
            }
        }

        // 4) Insert
        messages.append(incoming)
        sortMessagesInPlace()
    }

    private func sortMessagesInPlace() {
        // UI expects oldest -> newest.
        // Prefer createdAt if present, else id.
        messages.sort { a, b in
            let ad = parseISO(a.createdAt)
            let bd = parseISO(b.createdAt)

            if let ad, let bd, ad != bd { return ad < bd }
            return a.id < b.id
        }
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        // Try fractional seconds first, then fallback
        if let d = isoFormatter.date(from: s) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    // MARK: - Private helpers (socket decoding)

    private func handleIncomingMessageEvent(data: [Any], roomId: Int) {
        // SocketIO gives [Any]. We want the first object.
        guard let first = data.first else { return }

        // Sometimes payload is { item: {...} }
        if let dict = first as? [String: Any] {
            let msgDict = (dict["item"] as? [String: Any]) ?? dict
            if let msg: MessageDTO = decodeFromDictionary(msgDict) {
                if msg.chatRoomId == roomId {
                    insertOrReplace(msg)
                }
                return
            }
        }

        // If server already sends a JSON string
        if let str = first as? String,
           let msg: MessageDTO = decodeFromJSONString(str) {
            if msg.chatRoomId == roomId {
                insertOrReplace(msg)
            }
            return
        }
    }

    private func handleTypingEvent(data: [Any], roomId: Int, defaultIsTyping: Bool) {
        guard let first = data.first else { return }

        // Expect dict containing roomId + username + maybe isTyping
        guard let dict = first as? [String: Any] else { return }

        if let rid = dict["roomId"] as? Int, rid != roomId { return }

        let username = (dict["username"] as? String)
            ?? (dict["name"] as? String)
            ?? ""

        // If event is typing:update and includes isTyping, use it
        let isTyping = (dict["isTyping"] as? Bool) ?? defaultIsTyping
        applyTypingUpdate(username: username, isTyping: isTyping)
    }

    private func decodeFromDictionary<T: Decodable>(_ dict: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func decodeFromJSONString<T: Decodable>(_ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
