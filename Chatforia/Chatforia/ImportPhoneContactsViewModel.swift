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

    var selectedContacts: [PhoneContactDTO] {
        contacts.filter { selectedIDs.contains($0.id) }
    }

    func loadContacts() async {
        isLoading = true
        errorText = nil
        successText = nil
        defer { isLoading = false }

        let granted = await PhoneContactsService.shared.requestAccess()
        guard granted else {
            errorText = "Contacts access was not granted."
            contacts = []
            return
        }

        do {
            contacts = try PhoneContactsService.shared.fetchContacts()
        } catch {
            errorText = error.localizedDescription
            contacts = []
        }
    }

    func toggle(_ contact: PhoneContactDTO) {
        if selectedIDs.contains(contact.id) {
            selectedIDs.remove(contact.id)
        } else {
            selectedIDs.insert(contact.id)
        }
    }

    func selectAll() {
        selectedIDs = Set(contacts.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func importSelected(token: String?) async throws -> Int {
        guard let token, !token.isEmpty else {
            throw APIError.unauthorized
        }

        let chosen = selectedContacts
        guard !chosen.isEmpty else {
            throw NSError(
                domain: "ImportPhoneContactsViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Select at least one contact."]
            )
        }

        isImporting = true
        errorText = nil
        successText = nil
        defer { isImporting = false }

        var imported = 0

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
                print("⚠️ Failed to import \(contact.displayName):", error)
            }
        }

        successText = imported == 1 ? "Imported 1 contact." : "Imported \(imported) contacts."
        return imported
    }
}
