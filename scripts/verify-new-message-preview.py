#!/usr/bin/env python3
"""Compile the actual socket preview method with controlled collaborators."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Chatforia/Chatforia/ChatsViewModel.swift').read_text()
start = source.rfind('\n', 0, source.index('func bumpConversation(')) + 1
brace = source.index('{', start)
end, depth = brace + 1, 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end].replace('private func ', 'func ')
harness = r'''
import Foundation
@MainActor final class DecryptedMessageTextStore {
    static let shared = DecryptedMessageTextStore()
    var values: [Int:String] = [:]
    func text(for id: Int) -> String? { values[id] }
    func setText(_ text: String, for id: Int) { values[id] = text }
}
struct LocalMessage { let clientMessageId: String; let rawContent: String?; let translatedForMe: String? }
@MainActor final class MessageStore {
    static let shared = MessageStore()
    func currentWindow() -> [LocalMessage] { [] }
}
enum CryptoFailure: Error { case unavailable }
@MainActor final class MessageCryptoService {
    static let shared = MessageCryptoService()
    func decryptMessageForCurrentBackend(ciphertextBase64: String, encryptedKeyPayload: String, userId: Int) throws -> String {
        throw CryptoFailure.unavailable
    }
}
@MainActor final class PreviewVM {
    var conversations: [ConversationDTO] = []
    var refreshes = 0
    func scheduleLiveRefresh() { refreshes += 1 }
    func resortConversations() {}
    func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
METHOD
}
@main struct QA {
    @MainActor static func main() {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS: \(name)") }
        let vm = PreviewVM()
        func seed() {
            vm.conversations = [ConversationDTO(kind: "chat", id: 84, title: "regina",
                displayName: nil, updatedAt: "2026-10-20T17:00:00Z", isGroup: false,
                phone: nil, unreadCount: 0, avatarUsers: nil,
                last: ConversationLastDTO(text: "[voice note]", messageId: 90,
                    at: "2026-10-20T17:00:00Z", hasMedia: true, mediaCount: 1,
                    mediaKinds: ["AUDIO"], thumbUrl: "old-audio", senderName: "old sender"))]
        }
        func emit(_ fields: [String:Any], id: Int = 91) {
            var payload: [String:Any] = ["id":id, "createdAt":"2026-10-20T18:00:00Z"]
            payload.merge(fields) { _, new in new }
            vm.bumpConversation(roomId:84, payload:payload)
        }
        seed(); emit(["contentCiphertext":"encrypted"])
        check(vm.conversations[0].last?.text == "Message", "new encrypted text cannot inherit Voice note")
        check(vm.conversations[0].last?.hasMedia == false, "new text cannot inherit previous audio flag")
        check(vm.conversations[0].last?.mediaKinds == nil && vm.conversations[0].last?.thumbUrl == nil, "new text clears stale media kind and thumbnail")
        check(vm.conversations[0].last?.messageId == 91, "new preview retains new message identity")
        check(vm.conversations[0].last?.senderName == nil, "new message cannot inherit previous sender label")
        seed(); emit(["rawContent":"Test", "contentCiphertext":"encrypted"])
        check(vm.conversations[0].last?.text == "Test", "actual Test takes priority over encrypted fallback")
        seed(); DecryptedMessageTextStore.shared.setText("Test", for:91)
        emit(["contentCiphertext":"encrypted"])
        check(vm.conversations[0].last?.text == "Test", "new message uses its own decrypted cache")
        DecryptedMessageTextStore.shared.values = [:]
        seed(); emit(["contentCiphertext":"encrypted"], id:90)
        check(vm.conversations[0].last?.text == "[voice note]" && vm.conversations[0].last?.hasMedia == true, "same-message metadata retains known preview and media")
        seed(); emit(["rawContent":"Test", "attachments":[[String:Any]]()])
        check(vm.conversations[0].last?.text == "Test" && vm.conversations[0].last?.hasMedia == false && vm.conversations[0].last?.mediaKinds == nil, "explicit empty attachments clear previous audio metadata")
        seed(); emit(["attachments":[["kind":"IMAGE", "url":"new-image"]]])
        check(vm.conversations[0].last?.mediaKinds == ["IMAGE"] && vm.conversations[0].last?.thumbUrl == "new-image", "new attachments use their own media metadata")
        // Older timestamps are what determine activity; use one explicitly.
        seed(); vm.bumpConversation(roomId:84, payload:["id":89,"createdAt":"2026-10-19T17:00:00Z","rawContent":"older text"])
        check(vm.conversations[0].last?.messageId == 90, "older message cannot replace latest preview")
        print("11 native new-message preview checks passed")
    }
}
'''.replace('METHOD', method)
with tempfile.TemporaryDirectory(prefix='chatforia-new-preview-') as directory:
    temp = Path(directory)
    (temp / 'ConversationDTO.swift').write_text((root / 'Chatforia/Chatforia/ConversationDTO.swift').read_text())
    (temp / 'Harness.swift').write_text(harness)
    executable = temp / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        str(temp / 'ConversationDTO.swift'), str(temp / 'Harness.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
