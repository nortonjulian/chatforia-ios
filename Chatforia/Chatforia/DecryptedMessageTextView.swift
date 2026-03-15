import SwiftUI

struct DecryptMessageTextView: View {
    let msg: MessageDTO
    let fallbackColor: Color

    @StateObject private var store = DecryptedMessageTextStore.shared
    @State private var attempted = false

    var body: some View {
        Group {
            if let text = store.text(for: msg.id),
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
    }

    private func decryptIfNeeded() async {
        guard !attempted else { return }
        attempted = true

        guard let ciphertext = msg.contentCiphertext,
              let encryptedKeyPayload = msg.encryptedKeyForMe
        else {
            return
        }

        let currentUserId = UserDefaults.standard.integer(forKey: "chatforia.currentUserId")
        guard currentUserId > 0 else { return }

        do {
            print("🔓 attempting decrypt for message \(msg.id)")
            
            let plaintext = try MessageCryptoService.shared.decryptMessageForCurrentBackend(
                ciphertextBase64: ciphertext,
                encryptedKeyPayloadJSON: encryptedKeyPayload,
                userId: currentUserId
            )
            
            print("✅ decrypted message \(msg.id): \(plaintext)")

            await MainActor.run {
                DecryptedMessageTextStore.shared.setText(plaintext, for: msg.id)
            }
        } catch {
            print("❌ decrypt failed for message \(msg.id):", error)
        }
    }
}
