import Foundation
import Combine

@MainActor
final class PhoneNumberViewModel: ObservableObject {
    @Published var currentNumber: AssignedNumberDTO?
    @Published var availableNumbers: [AvailableNumberDTO] = []

    @Published var areaCode: String = ""
    @Published var selectedCountry: String = "US"
    @Published var selectedCapability: String = "sms"
    @Published var mode: NumberPickMode = .free

    @Published var isLoadingCurrent = false
    @Published var isSearching = false
    @Published var isLeasing = false
    @Published var errorText: String?

    var countryOptions: [CountryOption] {
        SupportedCountries.options
    }

    func loadCurrentNumber(token: String?) async {
        isLoadingCurrent = true
        errorText = nil
        defer { isLoadingCurrent = false }

        do {
            let response = try await PhoneNumberPoolService.shared.fetchMyNumber(token: token)
            currentNumber = response.number
        } catch {
            errorText = error.localizedDescription
        }
    }

    func search(token: String?) async {
        isSearching = true
        errorText = nil
        availableNumbers = []
        defer { isSearching = false }

        do {
            let trimmed = areaCode.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let response = try await PhoneNumberPoolService.shared.searchPool(
                country: selectedCountry,
                capability: selectedCapability,
                areaCode: trimmed.isEmpty ? nil : trimmed,
                forSale: mode.forSale,
                token: token
            )

            let items = response.numbers ?? []
            availableNumbers = items

            if items.isEmpty {
                errorText =
                    response.error ??
                    response.message ??
                    (mode == .buy
                        ? "No available inventory right now."
                        : "No free numbers in our pool for that area code right now.")
            }
        } catch {
            errorText = error.localizedDescription
            availableNumbers = []
        }
    }

    func lease(_ number: AvailableNumberDTO, token: String?) async -> Bool {
        guard let e164 = number.e164 ?? number.number else { return false }

        isLeasing = true
        errorText = nil
        defer { isLeasing = false }

        do {
            _ = try await PhoneNumberPoolService.shared.leaseNumber(e164: e164, token: token)
            await loadCurrentNumber(token: token)
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}
