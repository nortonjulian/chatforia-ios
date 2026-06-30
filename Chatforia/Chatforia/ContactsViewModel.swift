import Foundation
import Combine

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [ContactDTO] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var searchText: String = ""

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    func loadContacts(token: String?) async {
        guard let token, !token.isEmpty else {
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
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
        }
    }

    func openDirectChat(for contact: ContactDTO, token: String?) async throws -> ChatRoomDTO {
        guard let userId = contact.user?.id ?? contact.userId else {
            throw NSError(
                domain: "ContactsViewModel",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: appText(
                        "ios.contact_not_linked_to_chatforia_user",
                        languageCode: appLanguage
                    )
                ]
            )
        }

        guard let token, !token.isEmpty else {
            throw APIError.unauthorized
        }

        return try await ChatRoomService.shared.startDirectChat(
            userId: userId,
            token: token
        )
    }
    
    func deleteContact(_ contact: ContactDTO, token: String?) async {
        guard let token, !token.isEmpty else {
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
            return
        }

        do {
            try await ContactsService.shared.deleteContact(
                contactId: contact.id,
                token: token
            )

            contacts.removeAll { $0.id == contact.id }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func updateContact(
        _ contact: ContactDTO,
        alias: String?,
        externalName: String?,
        favorite: Bool?,
        token: String?
    ) async {
        guard let token, !token.isEmpty else {
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
            return
        }

        do {
            let updated = try await ContactsService.shared.updateContact(
                contact: contact,
                alias: alias,
                externalName: externalName,
                favorite: favorite,
                token: token
            )

            if let index = contacts.firstIndex(where: { $0.id == updated.id }) {
                contacts[index] = updated
            } else {
                contacts.insert(updated, at: 0)
            }
        } catch {
            errorText = error.localizedDescription
        }
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

        return appText("ios.unknown_contact", languageCode: appLanguage)
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

        return appText("tap_to_view_contact", languageCode: appLanguage)
    }
}
