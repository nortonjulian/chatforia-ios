import SwiftUI

struct DecryptMessageTextView: View {
    let msg: MessageDTO
    let fallbackColor: Color

    @StateObject private var store = DecryptedMessageTextStore.shared
    @State private var isDecrypting = false
    @State private var didAttemptDecrypt = false

    var body: some View {
        Group {
            if let text = preferredVisibleText(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LinkifiedMessageText(text: text)
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
        .task(id: decryptionKey) { @MainActor in
            decryptIfNeeded()
        }
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

    // A message keeps its ID after edits. Retry when its version, complete
    // encryption bundle, or cached text changes (including cache eviction).
    private var decryptionKey: [String] {
        [
            String(msg.id),
            String(msg.revision ?? 0),
            String(msg.editedAt?.timeIntervalSince1970 ?? 0),
            msg.encryptedPayloadForMe?.contentCiphertext ?? msg.contentCiphertext ?? "",
            msg.encryptedPayloadForMe?.encryptedKey ?? msg.encryptedKeyForMe ?? "",
            msg.rawContent ?? "",
            store.text(for: msg.id) ?? "",
            String(msg.deletedForAll == true || msg.deletedBySender == true),
            String(UserDefaults.standard.integer(forKey: "chatforia.currentUserId"))
        ]
    }

    @MainActor
    private func decryptIfNeeded() {
        isDecrypting = false
        didAttemptDecrypt = false

        guard msg.deletedForAll != true, msg.deletedBySender != true else {
            didAttemptDecrypt = true
            return
        }

        if let text = preferredVisibleText(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            didAttemptDecrypt = true
            return
        }

        let ciphertext = msg.encryptedPayloadForMe?.contentCiphertext ?? msg.contentCiphertext
        let encryptedKeyPayload = msg.encryptedPayloadForMe?.encryptedKey ?? msg.encryptedKeyForMe
        let currentUserId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")

        guard let ciphertext, let encryptedKeyPayload, currentUserId > 0 else {
            didAttemptDecrypt = true
            return
        }

        isDecrypting = true
        defer {
            isDecrypting = false
            didAttemptDecrypt = true
        }

        do {
            let plaintext = try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: ciphertext,
                encryptedKeyPayload: encryptedKeyPayload,
                userId: currentUserId
            )
            store.setText(plaintext, for: msg.id)
        } catch {
            // Keep the encrypted placeholder. A changed payload or cache
            // invalidation can trigger another attempt for this message ID.
        }
    }
}
