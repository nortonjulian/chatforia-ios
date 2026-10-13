import Foundation
import Combine

enum AddContactMode: String, CaseIterable, Identifiable {
    case username
    case phone

    var id: String { rawValue }

    var title: String {
        let language = UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"

        switch self {
        case .username:
            return appText("auth.username", languageCode: language)
        case .phone:
            return appText("contacts.phone", languageCode: language)
        }
    }
}

@MainActor
final class AddContactViewModel: ObservableObject {
    @Published var mode: AddContactMode
    @Published var username: String
    @Published var phoneNumber: String
    @Published var externalName: String
    @Published var alias: String
    @Published var favorite: Bool

    @Published var searchResults: [PeopleSearchItemDTO] = []
    @Published var selectedUser: PeopleSearchItemDTO?
    @Published var isSearching = false
    @Published var isSaving = false
    @Published var errorText: String?
    @Published var successText: String?

    private var searchTask: Task<Void, Never>?

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    init(
        mode: AddContactMode = .username,
        username: String = "",
        phoneNumber: String = "",
        externalName: String = "",
        alias: String = "",
        favorite: Bool = false
    ) {
        self.mode = mode
        self.username = username
        self.phoneNumber = phoneNumber
        self.externalName = externalName
        self.alias = alias
        self.favorite = favorite
    }

    var canSave: Bool {
        switch mode {
        case .username:
            return selectedUser?.userId != nil
        case .phone:
            return PhoneContactsService.normalizePhone(phoneNumber) != nil
        }
    }

    func usernameChanged(token: String?) {
        selectedUser = nil
        searchTask?.cancel()
        searchResults = []

        let query = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .username, query.count >= 3, let token, !token.isEmpty else {
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self else { return }
                self.isSearching = true
                defer { self.isSearching = false }

                let response = try await ContactsService.shared.searchPeople(
                    query: query,
                    token: token
                )

                guard !Task.isCancelled else { return }
                self.searchResults = response.items.filter {
                    $0.kind == "user" && $0.userId != nil
                }
                self.errorText = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.searchResults = []
                self.errorText = error.localizedDescription
            }
        }
    }

    func selectUser(_ user: PeopleSearchItemDTO) {
        selectedUser = user
        searchResults = []
        errorText = nil
    }

    func clearSelectedUser() {
        selectedUser = nil
        username = ""
        searchResults = []
        errorText = nil
    }

    func save(token: String?) async throws -> ContactDTO {
        guard let token, !token.isEmpty else {
            throw APIError.unauthorized
        }

        errorText = nil
        successText = nil
        isSaving = true
        defer { isSaving = false }

        switch mode {
        case .username:
            guard let userId = selectedUser?.userId else {
                throw NSError(
                    domain: "AddContactViewModel",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Select the person you want to save."
                    ]
                )
            }

            let contact = try await ContactsService.shared.saveUserContact(
                userId: userId,
                alias: alias.nilIfEmpty,
                favorite: favorite,
                token: token
            )

            successText = appText(
                "contacts.contactSaved",
                languageCode: appLanguage
            )
            return contact

        case .phone:
            guard let normalized = PhoneContactsService.normalizePhone(phoneNumber) else {
                throw NSError(
                    domain: "AddContactViewModel",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            appText(
                                "contacts.enterValidPhone",
                                languageCode: appLanguage
                            )
                    ]
                )
            }

            let contact = try await ContactsService.shared.saveExternalContact(
                phone: normalized,
                externalName: externalName.nilIfEmpty,
                alias: alias.nilIfEmpty,
                favorite: favorite,
                token: token
            )

            successText = appText(
                "contacts.contactSaved",
                languageCode: appLanguage
            )
            return contact
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
