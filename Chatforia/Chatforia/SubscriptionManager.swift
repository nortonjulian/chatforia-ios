import Foundation
import StoreKit
import Combine

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    private init() {
        listenForTransactions()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            await syncIfVerified(result, shouldFinish: false)
        }
    }

    private func listenForTransactions() {
        Task {
            for await result in Transaction.updates {
                await syncIfVerified(result, shouldFinish: true)
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

            print("❌ Failed to sync purchase:", error)
        }
    }

    private func planInfo(for productId: String) -> (plan: String, billingPeriod: String) {
        switch productId {
        case "chatforia_plus_monthly":
            return ("plus", "monthly")

        case "chatforia_plus_yearly":
            return ("plus", "yearly")

        case "chatforia_premium_monthly":
            return ("premium", "monthly")

        case "chatforia_premium_yearly":
            return ("premium", "yearly")

        default:
            return ("unknown", "unknown")
        }
    }
}
