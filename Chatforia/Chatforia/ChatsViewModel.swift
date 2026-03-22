import Foundation
import Combine

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var conversations: [ConversationDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String?
    @Published var searchText: String = ""

    static let conversationsBasePath = "conversations"

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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return conversations }

        return conversations.filter { item in
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

            if let conversations = response.conversations {
                self.conversations = conversations
            } else if let items = response.items {
                self.conversations = items
            } else {
                self.conversations = []
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

            errorText = nil
        } catch {
            errorText = "Failed to delete conversation."
            print("❌ deleteConversation failed:", error)
        }
    }
}

private struct ConversationsResponse: Decodable {
    let items: [ConversationDTO]?
    let conversations: [ConversationDTO]?
}
