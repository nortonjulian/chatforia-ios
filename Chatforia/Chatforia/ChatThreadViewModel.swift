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

    @Published var typingUsernames: [String] = []

    private var typingStopTask: Task<Void, Never>?
    private var hasSentTypingStart: Bool = false

    private var socketListenerIDs: [UUID] = []
    private var activeRoomId: Int?

    // ✅ keep base route consistent with ChatsViewModel
    private let basePath = ChatsViewModel.chatroomsBasePath

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
            self.messages = page.items
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
            translatedForMe: nil,        // ✅ add
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
            sender: nil,                 // ✅ add
            chatRoomId: roomId,
            randomChatRoomId: nil,
            createdAt: nil,
            isAutoReply: nil
        )
        
        messages.append(optimistic)

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

    /// Call when entering a room. Safe to call multiple times; it will rebind if room changes.
    func startSocket(roomId: Int, token: String?, myUsername: String?) {
        guard activeRoomId != roomId else { return }
        stopSocket() // clean previous room

        activeRoomId = roomId

        if let token {
            SocketManager.shared.connect(token: token)
        }

        SocketManager.shared.joinRoom(roomId: roomId)

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

    func applyTypingUpdate(username: String, isTyping: Bool) {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if isTyping {
            if !typingUsernames.contains(name) { typingUsernames.append(name) }
        } else {
            typingUsernames.removeAll { $0 == name }
        }
    }

    // MARK: - Private helpers

    private func insertOrReplace(_ incoming: MessageDTO) {
        if let idx = messages.firstIndex(where: { $0.id == incoming.id }) {
            messages[idx] = incoming
            return
        }

        if let cmid = incoming.clientMessageId,
           let idx = messages.firstIndex(where: { $0.clientMessageId == cmid }) {
            messages[idx] = incoming
            return
        }

        messages.append(incoming)
    }

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
