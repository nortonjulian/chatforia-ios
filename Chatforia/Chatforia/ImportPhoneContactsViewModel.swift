import Foundation
import Combine

@MainActor
final class ImportPhoneContactsViewModel: ObservableObject {
    @Published var contacts: [PhoneContactDTO] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorText: String?
    @Published var successText: String?
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var selectedContacts: [PhoneContactDTO] {
        contacts.filter { selectedIDs.contains($0.id) }
    }

    func loadContacts() async {
        guard !isLoading else { return }

        isLoading = true
        errorText = nil
        successText = nil
        defer { isLoading = false }

        let granted = await PhoneContactsService.shared.requestAccess()
        guard granted else {
            contacts = []
            selectedIDs.removeAll()
            errorText = appText(
                "contacts.accessNotGranted",
                languageCode: appLanguage
            )
            return
        }

        do {
            let fetched = try await PhoneContactsService.shared.fetchContacts()
            contacts = deduplicatedContacts(from: fetched)

            let validIDs = Set(contacts.map(\.id))
            selectedIDs = selectedIDs.intersection(validIDs)
        } catch {
            contacts = []
            selectedIDs.removeAll()
            errorText = error.localizedDescription
        }
    }

    func toggle(_ contact: PhoneContactDTO) {
        errorText = nil
        successText = nil

        if selectedIDs.contains(contact.id) {
            selectedIDs.remove(contact.id)
        } else {
            selectedIDs.insert(contact.id)
        }
    }

    func selectAll() {
        errorText = nil
        successText = nil
        selectedIDs = Set(contacts.map(\.id))
    }

    func clearSelection() {
        errorText = nil
        successText = nil
        selectedIDs.removeAll()
    }

    func importSelected(token: String?) async throws -> Int {
        guard !isImporting else { return 0 }

        guard let token, !token.isEmpty else {
            throw APIError.unauthorized
        }

        errorText = nil
        successText = nil

        let chosen = deduplicatedContacts(from: selectedContacts)
        guard !chosen.isEmpty else {
            throw NSError(
                domain: "ImportPhoneContactsViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: appText(
                    "contacts.selectAtLeastOne",
                    languageCode: appLanguage
                )]
            )
        }

        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var failedNames: [String] = []

        for contact in chosen {
            do {
                _ = try await ContactsService.shared.saveExternalContact(
                    phone: contact.phoneNumber,
                    externalName: contact.displayName,
                    alias: nil,
                    favorite: false,
                    token: token
                )
                imported += 1
            } catch {
                failedNames.append(contact.displayName)
                print("⚠️ Failed to import \(contact.displayName):", error)
            }
        }

        if imported > 0 {
            successText = imported == 1
                ? appText(
                    "contacts.importedOneContact",
                    languageCode: appLanguage
                )
                : String(
                    format: appText(
                        "contacts.importedContactsCount",
                        languageCode: appLanguage
                    ),
                    imported
                )
        } else {
            successText = nil
        }

        if failedNames.isEmpty {
            errorText = nil
        } else if imported > 0 {
            errorText = failedNames.count == 1
                ? appText(
                    "contacts.oneContactCouldNotImport",
                    languageCode: appLanguage
                )
                : String(
                    format: appText(
                        "contacts.contactsCouldNotImportCount",
                        languageCode: appLanguage
                    ),
                    failedNames.count
                )
        } else {
            errorText = failedNames.count == 1
                ? appText(
                    "contacts.couldNotImportSelectedContact",
                    languageCode: appLanguage
                )
                : appText(
                    "contacts.couldNotImportSelectedContacts",
                    languageCode: appLanguage
                )
        }
        return imported
    }

    private func deduplicatedContacts(from contacts: [PhoneContactDTO]) -> [PhoneContactDTO] {
        var seen = Set<String>()
        var result: [PhoneContactDTO] = []

        for contact in contacts {
            let normalized = normalizedPhoneNumber(contact.phoneNumber)

            guard !normalized.isEmpty else { continue }

            if seen.insert(normalized).inserted {
                result.append(contact)
            }
        }

        return result
    }

    private func normalizedPhoneNumber(_ phone: String) -> String {
        phone.filter(\.isNumber)
    }
}
