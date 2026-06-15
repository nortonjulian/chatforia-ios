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
        .onReceive(store.$values) { _ in } // 👈 THIS LINE
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

        let ciphertext =
            msg.encryptedPayloadForMe?.contentCiphertext
            ?? msg.contentCiphertext

        let encryptedKeyPayload =
            msg.encryptedPayloadForMe?.encryptedKey
            ?? msg.encryptedKeyForMe

        guard let ciphertext, let encryptedKeyPayload else {
            return
        }

        let currentUserId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")
        guard currentUserId > 0 else { return }
        
        print("🔐 has encryptedPayloadForMe:", msg.encryptedPayloadForMe != nil)
        print("🔐 has ciphertext:", ciphertext.isEmpty == false)
        print("🔐 has encrypted key:", encryptedKeyPayload.isEmpty == false)
        print("🔐 currentUserId:", currentUserId)
        print("🔐 encryptedKey preview:", String(encryptedKeyPayload.prefix(30)))

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
            print("❌ decrypt failed for message \(msg.id):", error.localizedDescription)
            print("❌ full error:", error)
        }
    }
}
