#!/usr/bin/env python3
"""macOS: compile the actual ChatsViewModel/DTO and extracted sound-ID policy.
Network, crypto, notification name and storage boundaries are controlled;
UIKit presentation/audio and real socket delivery require an iPhone build.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'Chatforia' / 'Chatforia'

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    return source[start:end]

vm_source = (SOURCES / 'ChatsViewModel.swift').read_text()
audio = (SOURCES / 'AudioPlayerService.swift').read_text()
notifications = (SOURCES / 'NotificationCoordinator.swift').read_text()
socket = (SOURCES / 'SocketManager.swift').read_text()
# Wiring checks supplement (not replace) the compiled behavior tests.
assert 'playIncomingChatTone(' in block(socket, 'socket.on("message:upsert")')
assert 'UIApplication.shared.applicationState == .active' in block(socket, 'socket.on("message:upsert")')
assert 'completionHandler([.banner, .badge])' in notifications
assert 'completionHandler([.banner, .sound, .badge])' in notifications
assert 'playIncomingChatTone(' in notifications
assert 'foregroundMessageNotification' in vm_source and 'socketDidReconnect' in vm_source
print('PASS: chat sound, APNs fallback, and live refresh wiring')

STUBS = r'''
import Foundation
import Combine
let qaDefaults = UserDefaults(suiteName: "chatforia.qa.live.\(UUID().uuidString)")!
enum UIApplication { static let didBecomeActiveNotification = Notification.Name("qa.didBecomeActive") }
func appText(_ key: String, languageCode: String) -> String { key }
func debugLog(_ items: Any...) {}
extension Notification.Name {
    static let conversationWasRead = Self("qa.read")
    static let socketMessageUpsert = Self("qa.upsert")
    static let socketMessageEdited = Self("qa.edited")
    static let socketMessageDeleted = Self("qa.deleted")
    static let socketMessageExpired = Self("qa.expired")
    static let socketSMSMessageNew = Self("qa.sms")
    static let foregroundMessageNotification = Self("qa.foreground")
    static let socketDidReconnect = Self("qa.reconnect")
    static let MessagesChanged = Self("qa.changed")
}
struct APIRequest {
    enum Method { case GET, PATCH, DELETE }
    let path: String
    let method: Method
    var body: Data? = nil
    let requiresAuth: Bool
}
struct EmptyResponse: Decodable {}
struct EncryptedPayload: Decodable { let contentCiphertext: String; let encryptedKey: String }
struct MessageDTO: Decodable {
    let id: Int
    var rawContent: String? = nil
    var translatedForMe: String? = nil
    var clientMessageId: String? = nil
    var chatRoomId: Int? = nil
    var contentCiphertext: String? = nil
    var encryptedKeyForMe: String? = nil
    var encryptedPayloadForMe: EncryptedPayload? = nil
    let createdAt: Date
}
struct MessagesPageResponse: Decodable { let items: [MessageDTO] }
@MainActor final class TokenStore {
    static let shared = TokenStore()
    var token: String? = "qa"
    func read() -> String? { token }
}
@MainActor final class MessageStore {
    static let shared = MessageStore()
    func currentWindow() -> [MessageDTO] { [] }
    func removeMessages(forRoomId: Int) {}
}
@MainActor final class DecryptedMessageTextStore {
    static let shared = DecryptedMessageTextStore()
    var cache: [Int: String] = [:]
    func text(for id: Int) -> String? { cache[id] }
    func setText(_ text: String, for id: Int) { cache[id] = text }
    func removeText(for id: Int) { cache.removeValue(forKey: id) }
}
@MainActor final class MessageCryptoService {
    static let shared = MessageCryptoService()
    func decryptMessageForCurrentBackend(ciphertextBase64: String, encryptedKeyPayload: String, userId: Int) throws -> String { throw QAError.network }
}
@MainActor final class SocketManager {
    static let shared = SocketManager()
    func connect(token: String) {}
    func joinRoom(_ roomId: Int) {}
}
enum QAError: Error { case network }
@MainActor final class APIClient {
    static let shared = APIClient()
    var responses: [(UInt64, Data)] = []
    var historyResponses: [(UInt64, Data)] = []
    var failNext = false
    var conversationRequests = 0
    func send<T: Decodable>(_ request: APIRequest, token: String) async throws -> T {
        let entry: (UInt64, Data)
        if request.path.hasPrefix("conversations?") {
            conversationRequests += 1
            if failNext { failNext = false; throw QAError.network }
            precondition(!responses.isEmpty, "Unexpected conversations request")
            entry = responses.removeFirst()
        } else {
            entry = historyResponses.isEmpty ? (0, Data("{\"items\":[]}".utf8)) : historyResponses.removeFirst()
        }
        if entry.0 > 0 { try? await Task.sleep(nanoseconds: entry.0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: entry.1)
    }
}
'''

HARNESS = r'''
import Foundation

@main struct LiveUpdateQA {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            passed += 1
            print("PASS: \(name)")
        }
        func conversation(_ id: Int, _ messageId: Int, _ text: String, _ unread: Int, _ at: String = "2026-10-17T22:00:00Z") -> ConversationDTO {
            ConversationDTO(kind: "chat", id: id, title: "Chat \(id)", displayName: nil,
                updatedAt: at, isGroup: false, phone: nil, unreadCount: unread, avatarUsers: nil,
                last: ConversationLastDTO(text: text, messageId: messageId, at: at,
                    hasMedia: false, mediaCount: nil, mediaKinds: nil, thumbUrl: nil, senderName: nil))
        }
        struct Envelope: Encodable { let items: [ConversationDTO] }
        func enqueue(_ rows: [ConversationDTO], delay: UInt64 = 0) throws {
            APIClient.shared.responses.append((delay, try JSONEncoder().encode(Envelope(items: rows))))
        }
        func wait() async { try? await Task.sleep(nanoseconds: 400_000_000) }
        func emit(_ name: Notification.Name, info: [AnyHashable: Any]? = nil) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: info)
        }
        qaDefaults.set(7, forKey: "chatforia.currentUserId")
        let vm = ChatsViewModel()
        let initial = conversation(10, 1, "old", 0)
        try enqueue([initial])
        await vm.loadConversations(token: "qa")
        check(vm.conversations.first?.last?.text == "old", "initial list loads")

        try enqueue([conversation(10, 2, "new preview", 1)])
        let payload: [String: Any] = ["item": ["id": 2, "chatRoomId": 10,
            "createdAt": "2026-10-17T22:01:00Z", "rawContent": "new preview"]]
        emit(.socketMessageUpsert, info: ["payload": payload])
        await wait()
        check(vm.conversations.first?.last?.text == "new preview", "incoming socket message updates list preview")
        check(vm.conversations.first?.unreadCount == 1, "incoming socket message fetches authoritative unread count")
        check(!vm.isLoading, "live refresh finishes without a stuck loading state")

        let before = APIClient.shared.conversationRequests
        try enqueue([conversation(10, 2, "new preview", 1)])
        emit(.socketMessageUpsert, info: ["payload": payload])
        emit(.socketMessageUpsert, info: ["payload": payload])
        emit(.foregroundMessageNotification)
        await wait()
        check(APIClient.shared.conversationRequests == before + 1, "socket/APNs aliases coalesce into one request")
        check(vm.conversations.first?.unreadCount == 1, "duplicate delivery does not double-count unread messages")

        try enqueue([conversation(10, 2, "new preview", 0)])
        emit(.conversationWasRead, info: ["roomId": 10])
        await wait()
        check(vm.conversations.first?.unreadCount == 0, "opening conversation clears badge and reconciles with server")

        try enqueue([conversation(10, 3, "push only", 1)])
        emit(.foregroundMessageNotification)
        await wait()
        check(vm.conversations.first?.last?.text == "push only", "foreground push recovers preview without socket upsert")

        try enqueue([conversation(10, 4, "reconnected", 2)])
        emit(.socketDidReconnect)
        await wait()
        check(vm.conversations.first?.last?.text == "reconnected" && vm.conversations.first?.unreadCount == 2,
              "reconnect recovers missed preview and unread count")

        try enqueue([conversation(10, 5, "resumed", 3)])
        emit(UIApplication.didBecomeActiveNotification)
        await wait()
        check(vm.conversations.first?.last?.text == "resumed", "returning to foreground refreshes list")

        try enqueue([conversation(10, 6, "stale", 9)], delay: 180_000_000)
        let stale = Task { @MainActor in await vm.loadConversations(token: "qa") }
        try? await Task.sleep(nanoseconds: 25_000_000)
        try enqueue([conversation(10, 7, "current", 0)])
        await vm.loadConversations(token: "qa")
        await stale.value
        check(vm.conversations.first?.last?.text == "current" && vm.conversations.first?.unreadCount == 0,
              "late old response cannot restore stale preview or badge")

        APIClient.shared.failNext = true
        emit(.socketDidReconnect)
        await wait()
        check(vm.conversations.first?.last?.text == "current", "failed refresh preserves existing list")
        try enqueue([conversation(10, 8, "retry", 1)])
        emit(.socketDidReconnect)
        await wait()
        check(vm.conversations.first?.last?.text == "retry", "a subsequent reconnect retries failed refresh")

        try enqueue([conversation(10, 9, "Message", 1)])
        APIClient.shared.historyResponses.append((180_000_000,
            Data("{\"items\":[{\"id\":9,\"rawContent\":\"delayed old decrypt\",\"createdAt\":\"2026-10-17T22:00:00Z\"}]}".utf8)))
        await vm.loadConversations(token: "qa")
        try? await Task.sleep(nanoseconds: 25_000_000)
        try enqueue([conversation(10, 10, "latest", 1)])
        await vm.loadConversations(token: "qa")
        await wait()
        check(vm.conversations.first?.last?.text == "latest", "late preview hydration cannot replace newer message")

        try enqueue([conversation(10, 10, "latest", 1, "2026-10-17T22:00:00Z"),
                     conversation(20, 11, "second", 0, "2026-10-17T22:02:00Z")])
        await vm.loadConversations(token: "qa")
        check(vm.conversations.first?.id == 20, "authoritative list sorts newest conversation first")

        var tones = IncomingChatToneLedger()
        check(tones.claim(messageId: 1, userId: 7), "first socket/APNs delivery claims one tone")
        check(!tones.claim(messageId: 1, userId: 7), "second delivery path cannot sound same message")
        check(tones.claim(messageId: 2, userId: 7), "a different message has independent tone eligibility")
        check(tones.claim(messageId: 1, userId: 8), "account identities do not suppress each other's tones")
        check(!tones.claim(messageId: 0, userId: 7) && !tones.claim(messageId: 3, userId: 0), "invalid IDs cannot claim tones")
        var reverse = IncomingChatToneLedger()
        check(reverse.claim(messageId: 4, userId: 7) && !reverse.claim(messageId: 4, userId: 7),
              "APNs-first and socket-first delivery both deduplicate")
        check(NotificationIDQA.chatMessageId(in: ["messageId": "123"]) == 123,
              "production APNs string message ID parses")
        check(NotificationIDQA.chatMessageId(in: ["messageId": 456]) == 456,
              "production APNs integer message ID parses")
        check(NotificationIDQA.chatMessageId(in: ["messageId": "bad"]) == nil,
              "missing or malformed APNs ID retains legacy presentation fallback")
        print("\(passed) native live-update and tone-policy checks passed")
    }
}
'''

if not shutil.which('xcrun'):
    raise SystemExit('Run this script on macOS with Xcode installed; native checks have not run here.')
with tempfile.TemporaryDirectory(prefix='chatforia-live-qa-') as temp:
    temp = Path(temp)
    # Only platform name/storage boundaries are adapted. Production method bodies remain intact.
    (temp / 'ChatsViewModel.swift').write_text(vm_source.replace('import UIKit\n', '').replace('UserDefaults.standard', 'qaDefaults'))
    (temp / 'ConversationDTO.swift').write_text((SOURCES / 'ConversationDTO.swift').read_text())
    (temp / 'Stubs.swift').write_text(STUBS)
    (temp / 'TonePolicy.swift').write_text('import Foundation\n' + block(audio, 'struct IncomingChatToneLedger') +
        '\n@MainActor final class NotificationIDQA {\n' + block(notifications, 'nonisolated static func chatMessageId') + '\n}\n')
    (temp / 'Harness.swift').write_text(HARNESS)
    executable = temp / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        *map(str, sorted(temp.glob('*.swift'))), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
