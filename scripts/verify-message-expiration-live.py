#!/usr/bin/env python3
"""Compile actual expiry methods with small Foundation-only collaborators."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Chatforia/Chatforia/ChatThreadViewModel.swift').read_text()
def method(name):
    # Keep the complete signature, regardless of its access modifier.
    start = source.rfind('\n', 0, source.index('func ' + name)) + 1
    brace = source.index('{', start)
    level = 1
    end = brace + 1
    while level:
        level += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func ', 'func ')
for text in ['self.handleMessageExpiredEvent(payload)', '!isExpired($0) && !expiredMessageIds.contains($0.id)',
             'isExpired(incoming) || expiredMessageIds.contains(incomingId)']:
    assert text in source, f'Missing expiry wiring: {text}'
print('PASS: expiry notification, fresh store snapshots, and late-upsert guards are wired', flush=True)
methods = '\n'.join(method(name) for name in ['startExpiryLoop','stopExpiryLoop','isExpired','pruneExpiredMessages','handleMessageExpiredEvent'])
swift = r'''
import Foundation
struct MessageDTO { let id: Int; let expiresAt: Date? }
@MainActor final class MessageStore {
    static let shared = MessageStore()
    var removed: [Int] = []
    func removeMessage(id: Int) { removed.append(id) }
}
@MainActor final class DecryptedMessageTextStore {
    static let shared = DecryptedMessageTextStore()
    var text: [Int:String] = [:]
    func removeText(for id: Int) { text.removeValue(forKey:id) }
}
@MainActor final class ExpiryVM {
    var messages: [MessageDTO] = []
    var roomId: Int? = 83
    var expiredMessageIds = Set<Int>()
    var expiryTask: Task<Void,Never>?
    var nowTick = Date()
''' + methods + r'''
}
@main struct QA {
    @MainActor static func main() async {
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name); print("PASS: \(name)")
        }
        let vm = ExpiryVM()
        let past = Date(timeIntervalSinceNow:-60), future = Date(timeIntervalSinceNow:60)
        vm.messages = [MessageDTO(id:42,expiresAt:past),MessageDTO(id:43,expiresAt:future),MessageDTO(id:44,expiresAt:nil)]
        DecryptedMessageTextStore.shared.text[42] = "expired plaintext"
        vm.pruneExpiredMessages()
        check(vm.messages.map(\.id) == [43,44], "deadline removes only expired content")
        check(DecryptedMessageTextStore.shared.text[42] == nil, "expiry clears decrypted text cache")
        check(MessageStore.shared.removed == [42], "expiry removes persisted message window row")
        vm.pruneExpiredMessages()
        check(MessageStore.shared.removed == [42], "duplicate local expiry is idempotent")
        let formatter = ISO8601DateFormatter()
        let pastText = formatter.string(from:past), futureText = formatter.string(from:future)
        vm.handleMessageExpiredEvent(["id":43,"chatRoomId":82,"expiresAt":pastText])
        check(vm.messages.count == 2, "another room cannot remove a message")
        vm.handleMessageExpiredEvent(["id":43,"chatRoomId":83,"expiresAt":futureText])
        check(vm.messages.count == 2, "future deadline is ignored")
        vm.handleMessageExpiredEvent(["id":43,"chatRoomId":83,"expiresAt":"invalid"])
        check(vm.messages.count == 2, "malformed deadline is ignored")
        vm.handleMessageExpiredEvent(["id":43,"chatRoomId":83,"expiresAt":pastText])
        check(vm.messages.map(\.id) == [44], "content-free scoped server event removes matching message")
        check(vm.expiredMessageIds.contains(43), "server expiry protects against a late upsert")
        vm.messages.append(MessageDTO(id:45,expiresAt:Date(timeIntervalSinceNow:0.15)))
        vm.startExpiryLoop()
        try? await Task.sleep(nanoseconds:1_350_000_000)
        check(vm.messages.map(\.id) == [44], "running clock removes content without a socket or refresh")
        vm.stopExpiryLoop()
        check(vm.expiryTask == nil, "leaving thread cancels expiry clock")
        check(!vm.isExpired(MessageDTO(id:46,expiresAt:nil)), "OFF and legacy messages remain")
        print("12 native expiration checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-expiry-qa-') as folder:
    temp = Path(folder)
    (temp/'Harness.swift').write_text(swift)
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',str(temp/'Harness.swift'),'-o',str(temp/'verify')],check=True)
    subprocess.run([str(temp/'verify')],check=True)
