import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var conversations: [ConversationDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var searchText: String = ""
    
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

                // ✅ Only bump if this edit affects the latest visible message
                let currentLastMessageId = self.conversations[index].last?.messageId
                guard currentLastMessageId == messageId else { return }

                self.bumpConversation(roomId: roomId, payload: raw)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .MessagesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resortConversations()
            }
            .store(in: &cancellables)
    }
    
    private func bumpConversation(roomId: Int, payload: [String: Any]) {
        guard let index = conversations.firstIndex(where: { $0.id == roomId }) else { return }

        let convo = conversations[index]
        let nowISO = ISO8601DateFormatter().string(from: Date())

        let currentLast = convo.last

        let newText: String? = {
            if let text = payload["rawContent"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }

            if let text = payload["translatedForMe"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }

            if payload["deletedForAll"] as? Bool == true {
                return "Message deleted"
            }

            if let attachments = payload["attachments"] as? [[String: Any]], !attachments.isEmpty {
                return "[media]"
            }

            if currentLast?.hasMedia == true {
                return currentLast?.text ?? "[media]"
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
            return "SMS #\(id)"
        default:
            return "Chat #\(id)"
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
            errorText = "Missing auth token."
            conversations = []
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response: ConversationsResponse = try await APIClient.shared.send(
                APIRequest(path: Self.conversationsBasePath, method: .GET, requiresAuth: true),
                token: token
            )

            let fetched: [ConversationDTO]
            if let conversations = response.conversations {
                fetched = conversations
            } else if let items = response.items {
                fetched = items
            } else {
                fetched = []
            }

            self.conversations = sortedConversations(fetched)
            
            SocketManager.shared.connect(token: token)

            for convo in fetched where convo.kind.lowercased() == "chat" {
                if let roomId = convo.id {
                    SocketManager.shared.joinRoom(roomId)
                }
            }
            
        } catch {
            errorText = error.localizedDescription
            #if DEBUG
            print("❌ loadConversations error:", error)
            #endif
        }
    }

    func archiveConversation(_ conversation: ConversationDTO, token: String?) async -> Bool {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            return false
        }

        guard let conversationId = conversation.id else {
            errorText = "Missing conversation id."
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
            print("❌ archiveConversation failed:", error)
            return false
        }
    }

    func deleteConversation(_ conversation: ConversationDTO, token: String?) async {
        guard let token else {
            errorText = "Missing auth token."
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
            errorText = "Failed to delete conversation."
            print("❌ deleteConversation failed:", error)
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
