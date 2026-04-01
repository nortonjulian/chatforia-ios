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
            .sink { [weak self] _ in
                self?.resortConversations()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .MessagesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resortConversations()
            }
            .store(in: &cancellables)
    }
    
    private func resortConversations() {
        conversations = sortedConversations(conversations)
    }

    private func searchableTitle(for item: ConversationDTO) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallbackTitle(for: item) : title
    }

    private func fallbackTitle(for item: ConversationDTO) -> String {
        switch item.kind.lowercased() {
        case "sms":
            if let phone = item.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                return phone
            }
            return "SMS #\(item.id)"
        default:
            return "Chat #\(item.id)"
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

        struct ArchiveRequest: Encodable {
            let archived: Bool
        }

        do {
            let body = try JSONEncoder().encode(ArchiveRequest(archived: true))

            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(conversation.kind.lowercased())/\(conversation.id)/archive",
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

        do {
            let _: EmptyResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "conversations/\(conversation.kind.lowercased())/\(conversation.id)",
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
                return lhs.id > rhs.id
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
