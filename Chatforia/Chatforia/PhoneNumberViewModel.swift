import Foundation
import Combine

struct NumberRegulatoryVerificationState {
    let e164: String
    let purchaseIntent: Bool
    let decision: String
    let requiresVerification: Bool
}

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
    @Published var regulatoryVerification: NumberRegulatoryVerificationState?
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    var countryOptions: [CountryOption] {
        SupportedCountries.options
    }

    var releaseDateString: String? {
        guard let number = currentNumber else { return nil }
        return number.releaseAfter ?? number.holdUntil
    }

    var daysUntilRelease: Int? {
        guard let dateString = releaseDateString,
              let date = ISO8601DateFormatter().date(from: dateString) else {
            return nil
        }

        let days = Int(ceil(date.timeIntervalSinceNow / (60 * 60 * 24)))
        return max(days, 0)
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
        debugLog("🔎 PhoneNumberViewModel.search() started")
        isSearching = true
        errorText = nil
        availableNumbers = []
        defer { isSearching = false }

        do {
            let trimmed = areaCode.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // 🔥 TRACK: user started searching
            AnalyticsManager.shared.capture("number_search_started", properties: [
                "country": selectedCountry,
                "capability": selectedCapability,
                "mode": mode == .premium ? "premium" : "free",
                "has_area_code": !trimmed.isEmpty
            ])

            let response = try await PhoneNumberPoolService.shared.searchPool(
                country: selectedCountry,
                capability: selectedCapability,
                areaCode: trimmed.isEmpty ? nil : trimmed,
                limit: 25,
                forSale: mode.forSale,
                token: token
            )

            let items = response.numbers ?? []
            availableNumbers = items

            if items.isEmpty {
                errorText =
                    response.error ??
                    response.message ??
                    (mode == .premium
                     ? appText(
                        "phoneNumber.noInventory",
                        languageCode: appLanguage
                    )
                     : appText(
                        "phoneNumber.noFreeNumbersForAreaCode",
                        languageCode: appLanguage
                    ))
            }
        } catch {
            errorText = error.localizedDescription
            availableNumbers = []
        }
    }

    func retryRegulatoryLease(token: String?) async -> Bool {
        guard let verification = regulatoryVerification else {
            return false
        }

        isLeasing = true
        errorText = nil
        defer { isLeasing = false }

        do {
            _ = try await PhoneNumberPoolService.shared.leaseNumber(
                e164: verification.e164,
                purchaseIntent: verification.purchaseIntent,
                token: token
            )

            AnalyticsManager.shared.capture(
                "number_selected",
                properties: [
                    "type":
                        verification.purchaseIntent
                        ? "premium"
                        : "free",
                    "country": selectedCountry
                ]
            )

            regulatoryVerification = nil
            await loadCurrentNumber(token: token)
            return true
        } catch let error as PhoneNumberLeaseError {
            if let regulatory = error.regulatoryResponse,
               let decision = regulatory.decision {
                regulatoryVerification =
                    NumberRegulatoryVerificationState(
                        e164: verification.e164,
                        purchaseIntent:
                            verification.purchaseIntent,
                        decision: decision,
                        requiresVerification:
                            regulatory.requiresVerification
                            ?? false
                    )
                errorText = nil
                return false
            }

            errorText = error.localizedDescription
            return false
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func lease(_ number: AvailableNumberDTO, token: String?) async -> Bool {
        guard let e164 = number.e164 ?? number.number else { return false }

        let purchaseIntent = mode == .premium

        isLeasing = true
        errorText = nil
        defer { isLeasing = false }

        do {
            _ = try await PhoneNumberPoolService.shared.leaseNumber(
                e164: e164,
                purchaseIntent: purchaseIntent,
                token: token
            )

            // 🔥 TRACK: user successfully selected / leased a number
            AnalyticsManager.shared.capture("number_selected", properties: [
                "type": mode == .premium ? "premium" : "free",
                "country": selectedCountry
            ])

            regulatoryVerification = nil
            await loadCurrentNumber(token: token)
            return true
        } catch let error as PhoneNumberLeaseError {
            if let regulatory = error.regulatoryResponse,
               let decision = regulatory.decision {
                regulatoryVerification =
                    NumberRegulatoryVerificationState(
                        e164: e164,
                        purchaseIntent: purchaseIntent,
                        decision: decision,
                        requiresVerification:
                            regulatory.requiresVerification ?? false
                    )
                errorText = nil
                return false
            }

            errorText = error.localizedDescription
            return false
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}
