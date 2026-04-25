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
        } catch {
            print("❌ Failed to sync purchase:", error)
        }
    }
}
