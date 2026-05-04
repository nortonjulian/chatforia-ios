import Foundation
import Combine

enum AddContactMode: String, CaseIterable, Identifiable {
    case username
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .username: return "Username"
        case .phone: return "Phone"
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
                    userInfo: [NSLocalizedDescriptionKey: "Enter a username."]
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

                successText = "Contact saved."
                return contact
            } catch let error as APIError {
                switch error {
                case .server(let status, _) where status == 404:
                    throw NSError(
                        domain: "AddContactViewModel",
                        code: 404,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "No Chatforia user found with that username. Use the Phone tab to save them by number."
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
                    userInfo: [NSLocalizedDescriptionKey: "Enter a valid phone number."]
                )
            }

            let contact = try await ContactsService.shared.saveExternalContact(
                phone: normalized,
                externalName: externalName.nilIfEmpty,
                alias: alias.nilIfEmpty,
                favorite: favorite,
                token: token
            )

            successText = "Contact saved."
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
