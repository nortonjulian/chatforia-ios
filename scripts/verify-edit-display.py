#!/usr/bin/env python3
"""Run cache regression cases against the actual Swift store and DTO on macOS."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'Chatforia' / 'Chatforia'
HARNESS = r'''
import Foundation

extension Notification.Name {
    static let MessagesChanged = Notification.Name("Chatforia.MessagesChanged")
}

@main
struct EditDisplayRegression {
    @MainActor
    static func main() {
        let store = DecryptedMessageTextStore.shared
        let sender = SenderDTO(id: 1, username: "test", publicKey: nil, avatarUrl: nil)
        let date = Date(timeIntervalSince1970: 1000)
        func message(revision: Int = 2, edited: Date? = Date(timeIntervalSince1970: 1000),
                     cipher: String = "cipher-2", key: String = "key-2",
                     deleted: Bool = false, payload: Bool = true) -> MessageDTO {
            MessageDTO(
                id: 42,
                encryptedPayloadForMe: payload ? EncryptedMessagePayloadForUser(
                    contentCiphertext: cipher, encryptedKey: key
                ) : nil,
                createdAt: date,
                editedAt: edited,
                deletedForAll: deleted,
                sender: sender,
                revision: revision
            )
        }
        let edited = message()
        var passed = 0
        func check(_ name: String, incoming: MessageDTO,
                   current: MessageDTO?, retains: Bool) {
            store.setText("edited text", for: 42)
            store.invalidateTextIfNeeded(for: incoming, current: current)
            precondition((store.text(for: 42) == "edited text") == retains, name)
            print("PASS: \(name)")
            passed += 1
        }
        check("duplicate socket edit preserves local save", incoming: edited, current: edited, retains: true)
        check("fresh-session reload of same revision preserves text", incoming: edited, current: edited, retains: true)
        check("receipt metadata on edited message preserves text",
              incoming: message(payload: false), current: edited, retains: true)
        check("new revision invalidates old text",
              incoming: message(revision: 3), current: edited, retains: false)
        check("new edit timestamp invalidates old text",
              incoming: message(edited: date.addingTimeInterval(1)), current: edited, retains: false)
        check("changed ciphertext invalidates old text",
              incoming: message(cipher: "cipher-3"), current: edited, retains: false)
        check("changed encryption key invalidates old text",
              incoming: message(key: "key-3"), current: edited, retains: false)
        check("deletion removes cached plaintext",
              incoming: message(deleted: true), current: edited, retains: false)
        check("unknown edited version invalidates unverified cache",
              incoming: edited, current: nil, retains: false)
        // Replay the same edit after the first version transition and local save.
        store.setText("old text", for: 42)
        store.invalidateTextIfNeeded(for: edited, current: message(revision: 1, edited: nil))
        precondition(store.text(for: 42) == nil)
        store.setText("edited text", for: 42)
        store.invalidateTextIfNeeded(for: edited, current: edited)
        precondition(store.text(for: 42) == "edited text")
        print("PASS: save followed by socket acknowledgement retains edited text")
        passed += 1
        store.clearAll()
        print("\(passed) cache regression cases passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-edit-display-') as tmp:
    tmp = Path(tmp)
    harness = tmp / 'EditDisplayRegression.swift'
    harness.write_text(HARNESS)
    binary = tmp / 'verify-edit-display'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        str(SOURCES / 'MessageDTO.swift'),
        str(SOURCES / 'DecryptedMessageTextStore.swift'),
        str(harness), '-o', str(binary)
    ], check=True)
    subprocess.run([str(binary)], check=True)
