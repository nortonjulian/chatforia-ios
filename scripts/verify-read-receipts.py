#!/usr/bin/env python3
"""Compile actual DTO/store on macOS; isolate disk/defaults from real app data."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'Chatforia' / 'Chatforia'
HARNESS = r'''
import Foundation
enum DeliveryState: String, Codable { case pending, sending, sent, delivered, read, failed }
func debugLog(_ values: Any...) {}

@main
struct ReceiptRegression {
    static func main() throws {
        let store = MessageStore.shared
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            print("PASS: \(name)")
        }
        if CommandLine.arguments[2] == "reload" {
            check(store.message(withId: 1)?.readBy?.map(\.id) == [8, 9], "cold process restores shared readers")
            check(store.message(withId: 1)?.rawContent == "edited text", "cold process preserves message text")
            check(store.message(withId: 1)?.encryptedKeyForMe == "key", "cold process preserves encryption key")
            return
        }
        let sender = SenderDTO(id: 7, username: "sender", publicKey: nil, avatarUrl: nil)
        func message(_ id: Int, deleted: Bool = false) -> MessageDTO {
            MessageDTO(id: id, contentCiphertext: "cipher", rawContent: "edited text",
                       encryptedKeyForMe: "key", createdAt: Date(timeIntervalSince1970: 1000),
                       editedAt: Date(timeIntervalSince1970: 1100), deletedForAll: deleted,
                       sender: sender, chatRoomId: 10, revision: 2, clientMessageId: "client-\(id)")
        }
        store.insertOrReplaceSync([message(1), message(2), message(3, deleted: true)])
        func readers(_ id: Int) -> [Int] { store.message(withId: id)?.readBy?.map(\.id) ?? [] }
        let original = try JSONEncoder().encode(store.message(withId: 1)!)
        store.applyReadReceipt(["messageId": 1, "reader": ["id": 8, "username": "reader"], "chatRoomId": 10])
        check(readers(1) == [8], "underscore event reader shape updates existing message")
        store.applyReadReceipt(["messageId": "1", "userId": "8", "roomId": "10"])
        check(readers(1) == [8], "colon alias does not duplicate the reader")
        store.applyReadReceipt(["messageIds": [1, 2], "readerId": 9, "roomId": 10])
        check(readers(1) == [8, 9] && readers(2) == [9], "bulk receipts target only supplied messages")
        store.applyReadReceipt(["messageId": 2, "userId": 8, "roomId": 99])
        check(readers(2) == [9], "wrong-room receipt ignored")
        store.applyReadReceipt(["messageId": 1, "userId": 7])
        check(readers(1) == [8, 9], "sender is not counted as a reader")
        store.applyReadReceipt(["messageId": 3, "userId": 8])
        check(readers(3).isEmpty, "deleted messages remain untouched")
        store.applyReadReceipt(["messageId": 999, "userId": 8])
        check(store.message(withId: 999) == nil, "receipt cannot create or resurrect a message")
        store.applyReadReceipt(["messageId": 1, "reader": ["username": "missing id"]])
        check(readers(1) == [8, 9], "malformed receipt ignored")
        func withoutReaders(_ data: Data) throws -> NSDictionary {
            var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            object.removeValue(forKey: "readBy")
            return object as NSDictionary
        }
        let contentPreserved = try withoutReaders(original) == withoutReaders(JSONEncoder().encode(store.message(withId: 1)!))
        check(contentPreserved, "receipt preserves every message field except readBy")
        var hidden = message(2); hidden.readBy = []
        store.upsertMessage(hidden)
        check(readers(2) == [9], "empty metadata update preserves an already disclosed receipt")
        let partial = message(1)
        store.upsertMessage(partial)
        check(readers(1) == [8, 9], "missing receipt field preserves known readers")
        check(store.message(withId: 1)?.editedAt == partial.editedAt, "edited-message metadata survives receipt updates")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='chatforia-receipts-') as tmp:
    tmp = Path(tmp)
    storage = tmp / 'storage'
    storage.mkdir()
    # Only the storage/defaults adapter changes in this test copy. Receipt,
    # merge and persistence functions execute exactly as supplied by production.
    source = (SOURCES / 'MessageStore.swift').read_text()
    source = source.replace(
        'FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!',
        'URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)'
    ).replace('UserDefaults.standard', 'UserDefaults(suiteName: "chatforia.receipts.regression")!')
    adapted = tmp / 'MessageStore.swift'
    adapted.write_text(source)
    harness = tmp / 'ReceiptRegression.swift'
    harness.write_text(HARNESS)
    binary = tmp / 'verify-read-receipts'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        str(SOURCES / 'MessageDTO.swift'), str(adapted), str(harness), '-o', str(binary)
    ], check=True)
    for mode in ['seed', 'reload']:
        subprocess.run([str(binary), str(storage), mode], check=True)
