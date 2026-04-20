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

        await syncWithBackend(transaction: transaction)

        if shouldFinish {
            await transaction.finish()
        }
    }

    private func syncWithBackend(transaction: Transaction) async {
        guard let token = TokenStore.shared.read(), !token.isEmpty else { return }

        let transactionKey = "chatforia.synced.tx.\(transaction.id)"
        if UserDefaults.standard.bool(forKey: transactionKey) {
            return
        }

        do {
            let signedTransactionInfo = try await fetchSignedTransactionInfo(for: transaction)

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

    /// Replace implementation with the exact StoreKit 2 signed payload retrieval
    /// method you choose in your app. This function exists so the rest of the flow
    /// stays stable while you wire in Apple’s signed transaction representation.
    private func fetchSignedTransactionInfo(for transaction: Transaction) async throws -> String {
        // TODO:
        // Return Apple-signed transaction JWS associated with this verified transaction.
        // Keep this isolated so you can swap implementation details without changing
        // the rest of SubscriptionManager.
        throw NSError(domain: "SubscriptionManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Signed transaction retrieval not implemented yet"
        ])
    }
}
