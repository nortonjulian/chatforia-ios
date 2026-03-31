import SwiftUI

struct DecryptMessageTextView: View {
    let msg: MessageDTO
    let fallbackColor: Color

    @StateObject private var store = DecryptedMessageTextStore.shared
    @State private var attempted = false

    var body: some View {
        Group {
            if let text = preferredVisibleText(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
            } else {
                Text("🔒 Encrypted message")
                    .foregroundStyle(fallbackColor)
                    .task {
                        await decryptIfNeeded()
                    }
            }
        }
        .task {
            await decryptIfNeeded()
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

    private func decryptIfNeeded() async {
        guard !attempted else { return }
        attempted = true

        guard msg.deletedForAll != true, msg.deletedBySender != true else {
            return
        }

        guard let ciphertext = msg.contentCiphertext,
              let encryptedKeyPayload = msg.encryptedKeyForMe else {
            return
        }

        let currentUserId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")
        guard currentUserId > 0 else { return }

        do {
            let plaintext = try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: ciphertext,
                encryptedKeyPayload: encryptedKeyPayload,
                userId: currentUserId
            )

            await MainActor.run {
                DecryptedMessageTextStore.shared.setText(plaintext, for: msg.id)
            }
        } catch {
            print("❌ decrypt failed for message \(msg.id):", error)
        }
    }
}
