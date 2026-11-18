import Foundation
import Combine

enum TabRefreshPolicy {
    static func shouldLoad(
        token: String?, loadedToken: String?, loadedAt: Date?,
        now: Date, freshness: TimeInterval = 60
    ) -> Bool {
        guard let token, !token.isEmpty else { return true }
        guard token == loadedToken, let loadedAt else { return true }
        let age = now.timeIntervalSince(loadedAt)
        return age < 0 || age >= freshness
    }
}

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [ContactDTO] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var searchText: String = ""

    private let fetchContacts: (String?, String) async throws -> ContactsResponseDTO
    private var sessionToken: String?
    private var loadedQuery: String?
    private var loadedAt: Date?
    private var loadingQuery: String?
    private var loadVersion = 0

    init(fetchContacts: @escaping (String?, String) async throws -> ContactsResponseDTO = { query, token in
        try await ContactsService.shared.fetchContacts(query: query, token: token)
    }) {
        self.fetchContacts = fetchContacts
    }

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    func prepareForSession(token: String?) {
        guard sessionToken != token else { return }
        loadVersion += 1
        sessionToken = token
        loadedQuery = nil
        loadedAt = nil
        loadingQuery = nil
        contacts = []
        errorText = nil
        isLoading = false
        searchText = ""
    }

    func loadContactsIfNeeded(token: String?, now: Date = Date()) async {
        prepareForSession(token: token)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loadedQuery != query || TabRefreshPolicy.shouldLoad(
            token: token, loadedToken: sessionToken, loadedAt: loadedAt, now: now
        ) else { return }
        await loadContacts(token: token)
    }

    func invalidateForNextOpen() { loadedAt = nil }

    func loadContacts(token: String?) async {
        guard let token, !token.isEmpty else {
            prepareForSession(token: nil)
            errorText = appText("ios.missing_auth_token", languageCode: appLanguage)
            contacts = []
            return
        }

        prepareForSession(token: token)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading || loadingQuery != query else { return }
        loadVersion += 1
        let version = loadVersion
        loadingQuery = query

        isLoading = true
        errorText = nil
        defer {
            if loadVersion == version {
                isLoading = false
                loadingQuery = nil
            }
        }

        do {
            let response = try await fetchContacts(query, token)
            guard sessionToken == token, loadVersion == version,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                  !Task.isCancelled else { return }
            contacts = response.items
            loadedQuery = query
            loadedAt = Date()
        } catch {
            guard sessionToken == token, loadVersion == version,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                  !Task.isCancelled else { return }
            errorText = error.localizedDescription
            contacts = []
            loadedQuery = nil
            loadedAt = nil
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
            token: token,
            displayName: displayName(for: contact)
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
            NotificationCenter.default.post(name: .callHistoryShouldRefresh, object: nil)
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
            NotificationCenter.default.post(name: .callHistoryShouldRefresh, object: nil)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func displayName(for contact: ContactDTO) -> String {
        if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            return alias
        }

        if let name = contact.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
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
