import Foundation
import Combine
import CryptoKit
import Security

enum AssignedNumberLookupState: Equatable {
    case loading
    case verifiedAssigned
    case verifiedUnassigned
    case unavailable
}

@MainActor
protocol AssignedNumberSnapshotStoring {
    func number(userId: Int, token: String) -> AssignedNumberDTO?
    func save(_ number: AssignedNumberDTO, userId: Int, token: String)
    func clear()
}

@MainActor
final class OfflineAssignedNumberStore: AssignedNumberSnapshotStoring {
    static let shared = OfflineAssignedNumberStore()

    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.chatforia.ios",
        account: String = "chatforia.assignedNumber.snapshot"
    ) {
        self.service = service
        self.account = account
    }

    private struct Snapshot: Codable {
        let userId: Int
        let tokenDigest: String
        let e164: String
        let status: String?
        let keepLocked: Bool?
        let releaseAfter: String?
        let holdUntil: String?

        func number() -> AssignedNumberDTO {
            AssignedNumberDTO(e164: e164, status: status, capabilities: nil,
                              keepLocked: keepLocked, releaseAfter: releaseAfter,
                              holdUntil: holdUntil)
        }
    }

    func number(userId: Int, token: String) -> AssignedNumberDTO? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.userId == userId,
              snapshot.tokenDigest == digest(token) else { return nil }
        return snapshot.number()
    }

    func save(_ number: AssignedNumberDTO, userId: Int, token: String) {
        let snapshot = Snapshot(userId: userId, tokenDigest: digest(token),
                                e164: number.e164, status: number.status,
                                keepLocked: number.keepLocked,
                                releaseAfter: number.releaseAfter,
                                holdUntil: number.holdUntil)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        var attributes = itemQuery
        SecItemDelete(attributes as CFDictionary)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemAdd(attributes as CFDictionary, nil)
        if result != errSecSuccess { debugLog("Assigned number snapshot save failed:", result) }
    }

    func clear() {
        SecItemDelete(itemQuery as CFDictionary)
    }

    private var itemQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct NumberRegulatoryVerificationState {
    let e164: String
    let purchaseIntent: Bool
    let decision: String
    let requiresVerification: Bool
}

@MainActor
final class PhoneNumberViewModel: ObservableObject {
    @Published var currentNumber: AssignedNumberDTO?
    @Published private(set) var lastKnownNumber: AssignedNumberDTO?
    @Published private(set) var lookupState: AssignedNumberLookupState = .loading
    var canPickNumber: Bool { lookupState == .verifiedUnassigned }
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

    private let fetchNumber: (String?) async throws -> MyAssignedNumberDTO
    private let snapshotStore: AssignedNumberSnapshotStoring
    private let accountIsCurrent: (String, Int) -> Bool
    private var activeLookup = UUID()
    private var activeAccountId: Int?
    private var activeToken: String?

    init(
        fetchNumber: @escaping (String?) async throws -> MyAssignedNumberDTO = {
            try await PhoneNumberPoolService.shared.fetchMyNumber(token: $0)
        },
        snapshotStore: AssignedNumberSnapshotStoring = OfflineAssignedNumberStore.shared,
        accountIsCurrent: @escaping (String, Int) -> Bool = { token, userId in
            TokenStore.shared.read() == token &&
            UserDefaults.standard.integer(forKey: "chatforia.currentUserId") == userId
        }
    ) {
        self.fetchNumber = fetchNumber
        self.snapshotStore = snapshotStore
        self.accountIsCurrent = accountIsCurrent
    }
    
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

    func loadCurrentNumber(token: String?, accountId: Int?) async {
        guard let token, !token.isEmpty, let accountId, accountId > 0 else {
            activeLookup = UUID()
            currentNumber = nil
            lastKnownNumber = nil
            lookupState = .unavailable
            isLoadingCurrent = false
            return
        }
        if activeAccountId != accountId || activeToken != token {
            currentNumber = nil
            lastKnownNumber = nil
        }
        activeAccountId = accountId
        activeToken = token
        let lookup = UUID()
        activeLookup = lookup
        lastKnownNumber = snapshotStore.number(userId: accountId, token: token)
            ?? currentNumber
        lookupState = .loading
        isLoadingCurrent = true
        errorText = nil
        defer { if activeLookup == lookup { isLoadingCurrent = false } }

        do {
            let response = try await fetchNumber(token)
            guard activeLookup == lookup, accountIsCurrent(token, accountId) else { return }
            currentNumber = response.number
            if let number = response.number {
                snapshotStore.save(number, userId: accountId, token: token)
                lastKnownNumber = nil
                lookupState = .verifiedAssigned
            } else {
                snapshotStore.clear()
                lastKnownNumber = nil
                lookupState = .verifiedUnassigned
            }
        } catch {
            guard activeLookup == lookup, accountIsCurrent(token, accountId) else { return }
            currentNumber = nil
            lookupState = .unavailable
            errorText = appText("phoneNumber.temporarilyUnavailable", languageCode: appLanguage)
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
        guard canChangeNumber(token: token) else {
            errorText = appText("phoneNumber.temporarilyUnavailable", languageCode: appLanguage)
            return false
        }
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
            await loadCurrentNumber(token: token, accountId: activeAccountId)
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
        guard canChangeNumber(token: token) else {
            errorText = appText("phoneNumber.temporarilyUnavailable", languageCode: appLanguage)
            return false
        }
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
            await loadCurrentNumber(token: token, accountId: activeAccountId)
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

    private func canChangeNumber(token: String?) -> Bool {
        guard let token, let accountId = activeAccountId,
              accountIsCurrent(token, accountId) else { return false }
        return lookupState == .verifiedAssigned || lookupState == .verifiedUnassigned
    }
}
