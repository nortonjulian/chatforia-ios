import Foundation
import Combine

// MARK: - API Models (keep here or move to shared models file)
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

// MARK: - ViewModel
@MainActor
final class ChatThreadViewModel: ObservableObject {
    // Public state
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    // Typing banner state
    @Published var typingUsernames: [String] = []

    // Expiry tick driver
    @Published private(set) var nowTick: Date = Date()
    private var expiryTask: Task<Void, Never>?

    // Typing emit housekeeping
    private var typingStopTask: Task<Void, Never>?
    private var hasSentTypingStart: Bool = false

    // Socket housekeeping
    private var socketListenerIDs: [UUID] = []
    private var activeRoomId: Int?

    // Typing auto-expire
    private var typingLastSeen: [String: Date] = [:]
    private var typingPruneTask: Task<Void, Never>?
    private let typingTTL: TimeInterval = 4.0

    // deterministic resync
    private var roomId: Int? = nil
    private var lastServerMessageId: Int = 0 {
        didSet {
            guard let roomId = roomId else { return }
            persistLastServerMessageId(lastServerMessageId, roomId: roomId)
        }
    }
    private var isResyncing: Bool = false

    // Formatter
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Expiry Loop
    func startExpiryLoop() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s
                await MainActor.run { self.nowTick = Date() }
            }
        }
    }

    func stopExpiryLoop() {
        expiryTask?.cancel()
        expiryTask = nil
    }

    func isExpired(_ msg: MessageDTO, now: Date = Date()) -> Bool {
        guard let s = msg.expiresAt else { return false }
        if let d = parseISO(s) { return d <= now }
        return false
    }

    // MARK: - Networking
    func loadMessages(roomId: Int, token: String?) async {
        // Defensive: ensure we have a valid numeric roomId
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
            for m in page.items { insertOrReplace(m) }

            if self.messages.isEmpty {
                self.errorText = "Loaded 0 messages for room \(roomId)."
                print("⚠️ loadMessages: 0 messages for roomId:", roomId)
            } else {
                print("✅ loadMessages: loaded \(self.messages.count) messages for roomId:", roomId)
            }
        } catch {
            errorText = error.localizedDescription
            print("❌ loadMessages error for roomId \(roomId):", error)
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
            createdAt: isoFormatter.string(from: Date()),
            isAutoReply: nil,
            revision: 1 // <-- add this
        )

        insertOrReplace(optimistic)

        do {
            let body = try JSONEncoder().encode(
                SendMessageRequest(chatRoomId: roomId, content: trimmed, clientMessageId: clientId)
            )

            let saved: MessageDTO = try await APIClient.shared.send(
                APIRequest(path: "messages", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            insertOrReplace(saved)
        } catch {
            messages.removeAll { $0.clientMessageId == clientId }
            errorText = error.localizedDescription
        }
    }

    // MARK: - Socket wiring
    func startSocket(roomId: Int, token: String?, myUsername: String?) {
        // Defensive: ensure we have a valid numeric roomId
        guard roomId > 0 else {
            print("❌ startSocket called with invalid roomId:", roomId)
            return
        }

        // If already connected to this room, nothing to do
        guard activeRoomId != roomId else { return }

        configureRoom(roomId: roomId)
        stopSocket()

        activeRoomId = roomId

        if let token { SocketManager.shared.connect(token: token) }
        SocketManager.shared.joinRoom(roomId: roomId)

        startTypingPruneLoop()
        startExpiryLoop()

        // message:upsert (canonical server upsert event)
        if let id = SocketManager.shared.on("message:upsert", callback: { [weak self] data, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleIncomingMessageEvent(data: data, roomId: roomId)
            }
        }) {
            socketListenerIDs.append(id)
        }

        // message:expired — optional but recommended (server may emit tombstones here)
        if let id = SocketManager.shared.on("message:expired", callback: { [weak self] data, _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleIncomingMessageEvent(data: data, roomId: roomId)
            }
        }) {
            socketListenerIDs.append(id)
        }

        // typing events
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

        // server emits: { roomId: N, item: { ...messageRow... } } OR messageRow directly
        if let dict = first as? [String: Any] {
            let msgDict = (dict["item"] as? [String: Any]) ?? dict
            if let msg: MessageDTO = decodeFromDictionary(msgDict) {
                if msg.chatRoomId == roomId { insertOrReplace(msg) }
                return
            }
        }

        if let str = first as? String, let msg: MessageDTO = decodeFromJSONString(str) {
            if msg.chatRoomId == roomId { insertOrReplace(msg) }
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

    // MARK: - Deterministic resync
    func configureRoom(roomId: Int) {
        guard self.roomId != roomId else { return }
        self.roomId = roomId
        self.lastServerMessageId = loadLastServerMessageId(roomId: roomId)
    }

    func resyncIfNeeded(token: String?) async {
        guard let token else { self.errorText = "Missing auth token."; return }
        guard let roomId = self.roomId, roomId > 0 else { return }
        guard !isResyncing else { return }

        isResyncing = true
        defer { isResyncing = false }

        SocketManager.shared.joinRoom(roomId: roomId)

        do {
            let path = "messages/\(roomId)?sinceId=\(lastServerMessageId)"
            let page: MessagesPageResponse = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )

            for msg in page.items {
                insertOrReplace(msg)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Insert / merge / helpers
    private func insertOrReplace(_ incoming: MessageDTO) {
        // Helper to get revision with default 1
        func rev(_ m: MessageDTO) -> Int { (m.revision ?? 1) }

        // 1) Try exact id match (server id or local negative optimistic id)
        if let idx = messages.firstIndex(where: { $0.id == incoming.id }) {
            let existing = messages[idx]
            // If incoming is newer, replace entire message with authoritative incoming
            if rev(incoming) > rev(existing) {
                messages[idx] = incoming
                bumpLastServerIdIfNeeded(messages[idx])
                sortMessagesInPlace()
            }
            return
        }

        // 2) Match by clientMessageId (optimistic send reconciliation)
        if let cmid = incoming.clientMessageId,
           let idx = messages.firstIndex(where: { $0.clientMessageId == cmid }) {
            let existing = messages[idx]
            // Usually server row (positive id + higher revision) should replace optimistic
            if rev(incoming) >= rev(existing) {
                // prefer authoritative incoming (server), but preserve local.createdAt if missing
                var replaced = incoming
                if (replaced.createdAt ?? "").isEmpty { replaced.createdAt = existing.createdAt }
                messages[idx] = replaced
                bumpLastServerIdIfNeeded(messages[idx])
                sortMessagesInPlace()
            }
            return
        }

        // 3) Fallback fuzzy reconcile: match recent negative-id local messages by content (existing behavior)
        if incoming.clientMessageId == nil,
           let incomingText = incoming.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !incomingText.isEmpty {
            if let idx = messages.lastIndex(where: { m in
                m.chatRoomId == incoming.chatRoomId &&
                (m.id < 0) &&
                (m.rawContent?.trimmingCharacters(in: .whitespacesAndNewlines) == incomingText)
            }) {
                let existing = messages[idx]
                if rev(incoming) >= rev(existing) {
                    messages[idx] = incoming
                    bumpLastServerIdIfNeeded(messages[idx])
                    sortMessagesInPlace()
                }
                return
            }
        }

        // 4) No match found — insert new authoritative row
        messages.append(incoming)
        bumpLastServerIdIfNeeded(incoming)
        sortMessagesInPlace()
    }
    
    private func sortMessagesInPlace() {
        messages.sort { a, b in
            let ad = parseISO(a.createdAt)
            let bd = parseISO(b.createdAt)
            if let ad, let bd, ad != bd { return ad < bd }
            return a.id < b.id
        }
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        if let d = isoFormatter.date(from: s) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    private func bumpLastServerIdIfNeeded(_ msg: MessageDTO) {
        if msg.id > 0 { lastServerMessageId = max(lastServerMessageId, msg.id) }
    }

    private func keyForLastId(_ roomId: Int) -> String { "chat.lastServerMessageId.\(roomId)" }
    private func loadLastServerMessageId(roomId: Int) -> Int { UserDefaults.standard.integer(forKey: keyForLastId(roomId)) }
    private func persistLastServerMessageId(_ id: Int, roomId: Int) { UserDefaults.standard.set(id, forKey: keyForLastId(roomId)) }

    // MARK: - Typing helpers
    func handleInputChanged(roomId: Int) {
        if !hasSentTypingStart {
            hasSentTypingStart = true
            SocketManager.shared.emit("typing:start", ["roomId": roomId])
        }

        typingStopTask?.cancel()
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self = self else { return }
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
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func decodeFromJSONString<T: Decodable>(_ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
