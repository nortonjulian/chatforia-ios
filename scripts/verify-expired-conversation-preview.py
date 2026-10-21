#!/usr/bin/env python3
"""Exercise actual conversation preview reconciliation with Foundation-only fixtures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Chatforia/Chatforia/ChatsViewModel.swift').read_text()
dto = (root / 'Chatforia/Chatforia/ConversationDTO.swift').read_text()

def method(name):
    start = source.rfind('\n', 0, source.index('func ' + name)) + 1
    brace = source.index('{', start)
    end, depth = brace + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func ', 'func ')

assert 'let newest = page.items.first(where: { $0.id == targetMessageId })' in source
assert 'newest.expiresAt.map({ $0 > Date() }) ?? true' in source
assert '?? page.items.first' not in source
print('PASS: hydration requires the exact authoritative message and rejects elapsed content', flush=True)

harness = r'''
import Foundation
@MainActor final class PreviewVM {
    var conversations: [ConversationDTO] = []
METHODS
}
@main struct QA {
    @MainActor static func main() throws {
        func check(_ value: Bool, _ name: String) {
            precondition(value, name); print("PASS: \(name)")
        }
        func row(_ id: Int? = 90, _ text: String? = "Test", kind: String = "chat", room: Int = 84, empty: Bool = false) -> ConversationDTO {
            ConversationDTO(kind: kind, id: room, title: "regina", displayName: nil,
                updatedAt: "2026-10-20T18:00:00Z", isGroup: false, phone: nil,
                unreadCount: 0, avatarUsers: nil,
                last: empty ? nil : ConversationLastDTO(text: text, messageId: id,
                    at: "2026-10-20T17:00:00Z", hasMedia: false, mediaCount: 0,
                    mediaKinds: nil, thumbUrl: nil, senderName: nil))
        }
        let vm = PreviewVM()
        vm.conversations = [row()]
        func merge(_ incoming: ConversationDTO) -> ConversationDTO {
            vm.preserveExistingPreviewWhenBackendHasPlaceholder([incoming])[0]
        }
        let cleared = merge(row(empty: true))
        check(cleared.last == nil, "authoritative empty history cannot restore expired Test")
        vm.conversations = [cleared]
        check(merge(row(empty: true)).last == nil, "repeated refresh keeps the expired preview absent")
        vm.conversations = [row()]
        check(merge(row(89, "Previous message")).last?.text == "Previous message", "previous surviving message replaces expired preview")
        check(merge(row(89, "Message")).last?.text == "Message", "different encrypted message cannot inherit expired plaintext")
        check(merge(row(90, "Message")).last?.text == "Test", "same identified encrypted message preserves known plaintext")
        check(merge(row(nil, "")).last?.text == "", "missing message ID cannot inherit cached text")
        check(merge(row(0, "")).last?.text == "", "invalid message ID cannot inherit cached text")
        check(merge(row(90, "New server text")).last?.text == "New server text", "real server text remains authoritative")
        check(merge(row(90, "", kind: "sms")).last?.text == "", "SMS reconciliation remains unchanged")
        check(merge(row(90, "Message", room: 83)).last?.text == "Message", "another room cannot inherit plaintext")
        check(!vm.shouldHydrateEncryptedPreview(row(empty: true)), "empty history never requests preview hydration")
        check(!vm.shouldHydrateEncryptedPreview(row(nil, "Message")), "unidentified placeholder never requests hydration")
        check(vm.shouldHydrateEncryptedPreview(row(89, "Message")), "identified encrypted predecessor remains eligible for hydration")
        check(!vm.shouldHydrateEncryptedPreview(row(89, "Voice note")), "readable media preview needs no hydration")
        let encoded = try JSONEncoder().encode(cleared)
        check(try JSONDecoder().decode(ConversationDTO.self, from: encoded).last == nil, "fresh DTO round trip keeps empty history empty")
        print("15 native conversation preview checks passed")
    }
}
'''.replace('METHODS', '\n'.join(method(n) for n in [
    'preserveExistingPreviewWhenBackendHasPlaceholder', 'shouldHydrateEncryptedPreview']))
# Throwing work must finish before passing the nonthrowing assertion argument.
harness = harness.replace('check(try JSONDecoder().decode(ConversationDTO.self, from: encoded).last == nil,',
    'let decoded = try JSONDecoder().decode(ConversationDTO.self, from: encoded)\n        check(decoded.last == nil,')
with tempfile.TemporaryDirectory(prefix='chatforia-preview-qa-') as directory:
    temp = Path(directory)
    (temp / 'ConversationDTO.swift').write_text(dto)
    (temp / 'Harness.swift').write_text(harness)
    executable = temp / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        str(temp / 'ConversationDTO.swift'), str(temp / 'Harness.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
