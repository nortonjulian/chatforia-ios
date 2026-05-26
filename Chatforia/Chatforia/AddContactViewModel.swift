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

    @Published var isSaving = false
    @Published var errorText: String?
    @Published var successText: String?
    
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
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .phone:
            return PhoneContactsService.normalizePhone(phoneNumber) != nil
        }
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
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedUsername.isEmpty else {
                throw NSError(
                    domain: "AddContactViewModel",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            appText(
                                "contacts.enterUsername",
                                languageCode: appLanguage
                            )
                    ]
                )
            }

            do {
                let lookup = try await ContactsService.shared.lookupUser(
                    username: trimmedUsername,
                    token: token
                )

                let contact = try await ContactsService.shared.saveUserContact(
                    userId: lookup.userId,
                    alias: alias.nilIfEmpty,
                    favorite: favorite,
                    token: token
                )

                successText = appText(
                    "contacts.contactSaved",
                    languageCode: appLanguage
                )
                return contact

            } catch let error as APIError {
                switch error {
                case .server(let status, _) where status == 404:
                    throw NSError(
                        domain: "AddContactViewModel",
                        code: 404,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                appText(
                                    "contacts.noUserFoundUsePhone",
                                    languageCode: appLanguage
                                )
                        ]
                    )

                default:
                    throw error
                }
            }

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
