import Foundation
import Contacts

final class PhoneContactsService {
    static let shared = PhoneContactsService()
    private init() {}

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func fetchContacts() async throws -> [PhoneContactDTO] {
        try await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]

            let request = CNContactFetchRequest(keysToFetch: keys)

            var results: [PhoneContactDTO] = []

            try store.enumerateContacts(with: request) { contact, _ in
                let fullName = [contact.givenName, contact.familyName]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let displayName = fullName.isEmpty ? "Unknown" : fullName

                for phoneValue in contact.phoneNumbers {
                    let raw = phoneValue.value.stringValue
                    let normalized = Self.normalizePhone(raw)
                    guard let normalized, !normalized.isEmpty else { continue }

                    let id = "\(contact.identifier)-\(normalized)"
                    results.append(
                        PhoneContactDTO(
                            id: id,
                            displayName: displayName,
                            phoneNumber: normalized
                        )
                    )
                }
            }

            return results.sorted {
                if $0.displayName == $1.displayName {
                    return $0.phoneNumber < $1.phoneNumber
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }.value
    }

    static func normalizePhone(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hasLeadingPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }

        if hasLeadingPlus {
            return "+\(digits)"
        }

        if digits.count == 10 {
            return "+1\(digits)"
        }

        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }

        return "+\(digits)"
    }
}
