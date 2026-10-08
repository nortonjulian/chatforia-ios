import Foundation
import StoreKit
import Combine

struct PlanUsageSnapshot: Decodable, Equatable {
    let used: Int
    let limit: Int
    let remaining: Int
}

struct AppPlanEntitlementsSnapshot: Decodable, Equatable {
    let riaActions: Int
    let translationChars: Int
    let hostedParticipantMinutes: Int
    let smsMessages: Int
    let pstnMinutes: Int
    let forwardingMinutes: Int
    let voicemailTranscriptionMinutes: Int
    let cloudStorageBytes: Int64
    let messageHistoryDays: Int?
    let adsEnabled: Bool
    let aiRewriteLevel: String
    let supportLevel: String
}

struct PlanEntitlementsResponse: Decodable, Equatable {
    let plan: String
    let entitlements: AppPlanEntitlementsSnapshot
    let monthKey: String
    let usage: [String: PlanUsageSnapshot]

    var appPlan: AppPlan {
        AppPlan(serverValue: plan)
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var backendEntitlements: PlanEntitlementsResponse?

    private init() {
        listenForTransactions()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            await syncIfVerified(result, shouldFinish: false)
        }

        await refreshBackendEntitlements()
    }

    private func listenForTransactions() {
        Task {
            for await result in Transaction.updates {
                await syncIfVerified(result, shouldFinish: true)
                await refreshBackendEntitlements()
            }
        }
    }

    private func syncIfVerified(
        _ transactionResult: VerificationResult<Transaction>,
        shouldFinish: Bool
    ) async {
        guard case .verified(let transaction) = transactionResult else { return }

        await syncWithBackend(
            transaction: transaction,
            signedTransactionInfo: transactionResult.jwsRepresentation
        )

        if shouldFinish {
            await transaction.finish()
        }
    }

    private func syncWithBackend(
        transaction: Transaction,
        signedTransactionInfo: String
    ) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else { return }

        let transactionKey = "chatforia.synced.tx.\(transaction.id)"
        if UserDefaults.standard.bool(forKey: transactionKey) {
            return
        }

        do {
            let payload: [String: Any] = [
                "signedTransactionInfo": signedTransactionInfo,
                "source": "ios_storekit2"
            ]

            _ = try await APIClient.shared.sendRaw(
                APIRequest(
                    path: "billing/ios-sync",
                    method: .POST,
                    body: try JSONSerialization.data(withJSONObject: payload),
                    requiresAuth: true
                ),
                token: token
            )

            UserDefaults.standard.set(true, forKey: transactionKey)

            let planInfo = planInfo(for: transaction.productID)

            AnalyticsManager.shared.capture("purchase_completed", properties: [
                "platform": "ios",
                "provider": "apple",
                "productId": transaction.productID,
                "plan": planInfo.plan,
                "billingPeriod": planInfo.billingPeriod
            ])

            AnalyticsManager.shared.capture("purchase_sync_resolved", properties: [
                "source": "ios",
                "provider": "apple"
            ])

        } catch {
            AnalyticsManager.shared.capture("purchase_sync_failed", properties: [
                "source": "ios",
                "provider": "apple",
                "productId": transaction.productID
            ])

            debugLog("❌ Failed to sync purchase:", error)
        }
    }

    func refreshBackendEntitlements() async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else {
            backendEntitlements = nil
            return
        }

        do {
            let response: PlanEntitlementsResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "premium/entitlements",
                    method: .GET,
                    requiresAuth: true
                ),
                token: token
            )

            backendEntitlements = response
        } catch {
            debugLog("⚠️ Failed to refresh backend plan entitlements:", error)
        }
    }

    internal func planInfo(for productId: String) -> (plan: String, billingPeriod: String) {
        switch productId {
        case "plus.monthly":
            return ("plus", "monthly")

        case "premium.monthly":
            return ("premium", "monthly")

        case "premium.annual":
            return ("premium", "annual")

        default:
            return ("unknown", "unknown")
        }
    }
}
