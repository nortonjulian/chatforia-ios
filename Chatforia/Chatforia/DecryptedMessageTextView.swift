import SwiftUI

struct DecryptMessageTextView: View {
    let msg: MessageDTO
    let fallbackColor: Color

    @StateObject private var store = DecryptedMessageTextStore.shared
    @State private var attempted = false
    @State private var isDecrypting = false
    @State private var didAttemptDecrypt = false

    var body: some View {
        Group {
            if let text = preferredVisibleText(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
            } else if isDecrypting || !didAttemptDecrypt {
                Text("Loading message")
                    .foregroundStyle(.clear)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            } else {
                Text("🔒 Encrypted message")
                    .foregroundStyle(fallbackColor)
            }
        }
        .task(id: msg.id) {
            await decryptIfNeeded()
        }
        .onReceive(store.$values) { _ in }
    }

    private func preferredVisibleText() -> String? {
        if let cached = store.text(for: msg.id),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }

        if let raw = msg.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }

        return nil
    }

    private func waitForMinimumLoadingTime(startedAt: Date) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, 0.35 - elapsed)

        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
    }

    private func decryptIfNeeded() async {
        if let text = preferredVisibleText(),
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            didAttemptDecrypt = true
            isDecrypting = false
            return
        }

        guard !attempted else { return }

        attempted = true
        isDecrypting = true

        let startedAt = Date()

        guard msg.deletedForAll != true, msg.deletedBySender != true else {
            await waitForMinimumLoadingTime(startedAt: startedAt)
            isDecrypting = false
            didAttemptDecrypt = true
            return
        }

        let ciphertext =
            msg.encryptedPayloadForMe?.contentCiphertext
            ?? msg.contentCiphertext

        let encryptedKeyPayload =
            msg.encryptedPayloadForMe?.encryptedKey
            ?? msg.encryptedKeyForMe

        guard let ciphertext, let encryptedKeyPayload else {
            await waitForMinimumLoadingTime(startedAt: startedAt)
            isDecrypting = false
            didAttemptDecrypt = true
            return
        }

        let currentUserId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")

        guard currentUserId > 0 else {
            await waitForMinimumLoadingTime(startedAt: startedAt)
            isDecrypting = false
            didAttemptDecrypt = true
            return
        }

        debugLog("🔐 has encryptedPayloadForMe:", msg.encryptedPayloadForMe != nil)
        debugLog("🔐 has ciphertext:", ciphertext.isEmpty == false)
        debugLog("🔐 has encrypted key:", encryptedKeyPayload.isEmpty == false)
        debugLog("🔐 currentUserId:", currentUserId)

        do {
            let plaintext = try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: ciphertext,
                encryptedKeyPayload: encryptedKeyPayload,
                userId: currentUserId
            )

            await waitForMinimumLoadingTime(startedAt: startedAt)

            await MainActor.run {
                DecryptedMessageTextStore.shared.setText(plaintext, for: msg.id)
                isDecrypting = false
                didAttemptDecrypt = true
            }
        } catch {
            debugLog("❌ decrypt failed for message \(msg.id):", error.localizedDescription)
            debugLog("❌ full error:", error)

            await waitForMinimumLoadingTime(startedAt: startedAt)

            isDecrypting = false
            didAttemptDecrypt = true
        }
    }
}
