import Foundation
import Combine

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [ContactDTO] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var searchText: String = ""

    func loadContacts(token: String?) async {
        guard let token, !token.isEmpty else {
            errorText = "Missing auth token."
            contacts = []
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response = try await ContactsService.shared.fetchContacts(
                query: searchText,
                token: token
            )
            contacts = response.items
        } catch {
            errorText = error.localizedDescription
            contacts = []
            print("❌ loadContacts error:", error)
        }
    }

    func openDirectChat(for contact: ContactDTO, token: String?) async throws -> ChatRoomDTO {
        guard let userId = contact.user?.id ?? contact.userId else {
            throw NSError(
                domain: "ContactsViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This contact is not linked to a Chatforia user."]
            )
        }

        guard let token, !token.isEmpty else {
            throw APIError.unauthorized
        }

        let room: DirectChatRoomResponseDTO = try await APIClient.shared.send(
            APIRequest(path: "chatrooms/direct/\(userId)", method: .POST, requiresAuth: true),
            token: token
        )

        return room.asChatRoomDTO
    }

    func displayName(for contact: ContactDTO) -> String {
        if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            return alias
        }

        if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }

        if let externalName = contact.externalName?.trimmingCharacters(in: .whitespacesAndNewlines), !externalName.isEmpty {
            return externalName
        }

        if let externalPhone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !externalPhone.isEmpty {
            return externalPhone
        }

        return "Unknown Contact"
    }

    func subtitle(for contact: ContactDTO) -> String {
        if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty,
           username != displayName(for: contact) {
            return "@\(username)"
        }

        if let externalPhone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !externalPhone.isEmpty {
            return externalPhone
        }

        return "Tap to view contact"
    }
}
