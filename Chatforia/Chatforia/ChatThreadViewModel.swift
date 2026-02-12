import Foundation
import Combine

struct MessagesResponse: Decodable {
    let messages: [MessageDTO]
}

struct SendMessageRequest: Encodable {
    let rawContent: String
    let clientMessageId: String
}

struct SendMessageResponse: Decodable {
    let message: MessageDTO
}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?

    @Published var typingUsernames: [String] = []

    private var typingStopTask: Task<Void, Never>?
    private var hasSentTypingStart: Bool = false

    // ✅ keep base route consistent with ChatsViewModel
    private let basePath = ChatsViewModel.chatroomsBasePath

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

    func loadMessages(roomId: Int, token: String?) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let path = "chatrooms/\(roomId)/messages"

        do {
            // 1) Try wrapped: { "messages": [...] }
            if let wrapped: MessagesResponse = try? await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            ) {
                self.messages = wrapped.messages
                if self.messages.isEmpty {
                    self.errorText = "Loaded 0 messages (wrapped shape) for room \(roomId)."
                }
                return
            }

            // 2) Try array: [ ... ]
            let arr: [MessageDTO] = try await APIClient.shared.send(
                APIRequest(path: path, method: .GET, requiresAuth: true),
                token: token
            )
            self.messages = arr

            if self.messages.isEmpty {
                self.errorText = "Loaded 0 messages (array shape) for room \(roomId)."
            }

        } catch {
            errorText = error.localizedDescription
        }
    }

    func handleInputChanged(roomId: Int) {
        if !hasSentTypingStart {
            hasSentTypingStart = true
            SocketManager.shared.emit("typing:start", ["roomId": roomId])
        }

        typingStopTask?.cancel()
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            await MainActor.run { self.hasSentTypingStart = false }
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

    func sendMessage(roomId: Int, token: String?, text: String) async {
        guard let token else {
            errorText = "Missing auth token."
            return
        }

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
            chatRoomId: roomId,
            randomChatRoomId: nil,
            createdAt: nil,
            isAutoReply: nil
        )

        self.messages.append(optimistic)

        do {
            let body = try JSONEncoder().encode(
                SendMessageRequest(rawContent: trimmed, clientMessageId: clientId)
            )

            let resp: SendMessageResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "\(basePath)/\(roomId)/messages",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )

            insertOrReplace(resp.message)

        } catch {
            self.messages.removeAll { $0.clientMessageId == clientId }
            errorText = error.localizedDescription
        }
    }
}
