#!/usr/bin/env python3
"""Compile actual SMS load and list-read methods with Foundation fixtures on Mac."""
from pathlib import Path
import shutil, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
src = root / 'Chatforia/Chatforia'
thread = (src / 'SMSThreadViewModel.swift').read_text()
chats = (src / 'ChatsViewModel.swift').read_text()
load = thread[thread.index('    func loadThread('):thread.index('    func sendTextMessage(')]
apply = chats[chats.index('    private func applySMSRead('):chats.index('    private func scheduleLiveRefresh(')].replace('private func applySMSRead', 'func applySMSRead', 1)
assert 'publisher(for: Notification.Name("smsThreadWasRead"))'  in chats
assert 'self.applySMSRead(threadId: threadId, accountId: accountId)' in chats
assert load.index('TokenStore.shared.read() == token') < load.index('name: Notification.Name("smsThreadWasRead")' )
assert load.index('thread = fetched') < load.index('name: Notification.Name("smsThreadWasRead")' )
assert 'fetched.id == threadId' in load
assert 'accountId' in load and 'scheduleLiveRefresh()' in apply
schedule = chats[chats.index('    private func scheduleLiveRefresh('):chats.index('    private func bumpConversation(')]
assert schedule.index('conversationLoadVersion += 1') < schedule.index('Task.sleep')
assert 'requestVersion == conversationLoadVersion' in chats
print('PASS: confirmed SMS reads update only their list row and invalidate stale list responses', flush=True)
if '--wiring-only' in sys.argv: raise SystemExit(0)
STUBS = r'''
import Foundation
extension Notification.Name { static let smsThreadWasRead = Notification.Name("smsThreadWasRead") }
struct SMSMessageDTO: Decodable { let id: Int }
struct SMSThreadDTO: Decodable { let id: Int; let sortedMessages: [SMSMessageDTO] }
struct APIRequest { let path: String; let method: HTTPMethod; let requiresAuth: Bool }
enum HTTPMethod { case GET }
enum APIError: Error { case network(Error); case server }
@MainActor final class TokenStore {
 static let shared = TokenStore(); var token: String? = "a"
 func read() -> String? { token }
}
@MainActor final class NotificationCoordinator {
 static let shared = NotificationCoordinator()
 func refreshBadgeState() async {}
}
@MainActor final class APIClient {
 static let shared = APIClient()
 struct Plan { let result: Result<SMSThreadDTO, Error>; var delay: UInt64 = 0 }
 var plans: [Plan] = []; var calls = 0
 func send<T: Decodable>(_ request: APIRequest, token: String) async throws -> T {
  calls += 1; let plan = plans.removeFirst()
  if plan.delay > 0 { try? await Task.sleep(nanoseconds: plan.delay) }
  return try plan.result.get() as! T
 }
}
func appText(_ key: String, languageCode: String) -> String { key }
func friendlyErrorMessage(_ error: Error) -> String { "Visible failure" }
final class ReadNotes: @unchecked Sendable {
 var notes: [Notification] = []
}
@MainActor final class RefreshQA {
 var thread: SMSThreadDTO?; var messages: [SMSMessageDTO] = []
 var isLoading = false; var errorText: String?; var refreshVersion = 0
 var appLanguage = "en"
'''
HARNESS = r'''
@main struct QA {
 @MainActor static func main() async {
  let key = "chatforia.currentUserId"
  let oldValue = UserDefaults.standard.object(forKey: key)
  defer { if let oldValue { UserDefaults.standard.set(oldValue, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
  UserDefaults.standard.set(1, forKey: key)
  let notes = ReadNotes()
  let observer = NotificationCenter.default.addObserver(forName: .smsThreadWasRead, object: nil, queue: nil) { notes.notes.append($0) }
  defer { NotificationCenter.default.removeObserver(observer) }
  var count = 0
  func check(_ ok: Bool, _ label: String) {
   precondition(ok, label); count += 1; print("PASS: \(label)")
  }
  let api = APIClient.shared
  func success(_ id: Int = 34, delay: UInt64 = 0) {
   api.plans.append(.init(result: .success(.init(id: id, sortedMessages: [.init(id: 80)])), delay: delay))
  }
  func entered(_ calls: Int) async { while api.calls < calls { await Task.yield() } }
  let refresh = RefreshQA()
  success(); await refresh.loadThread(threadId: 34, token: "a")
  check(notes.notes.count == 1, "successful history load publishes the SMS read")
  check(notes.notes[0].userInfo?["threadId"] as? Int == 34 && notes.notes[0].userInfo?["accountId"] as? Int == 1, "read identifies the exact SMS thread and account")
  notes.notes.removeAll()
  api.plans.append(.init(result: .failure(APIError.server)))
  await refresh.loadThread(threadId: 34, token: "a")
  check(notes.notes.isEmpty, "failed history cannot clear unread state")
  success(35); await refresh.loadThread(threadId: 34, token: "a")
  check(notes.notes.isEmpty, "wrong-thread response cannot acknowledge a read")
  let calls = api.calls
  await refresh.loadThread(threadId: 34, token: nil)
  check(api.calls == calls && notes.notes.isEmpty, "signed-out load never publishes a read")
  var target = api.calls + 1
  success(delay: 40_000_000)
  let cancelled = Task { await refresh.loadThread(threadId: 34, token: "a") }
  await entered(target); cancelled.cancel(); await cancelled.value
  check(notes.notes.isEmpty, "cancelled load never clears unread state")
  target = api.calls + 1; success(delay: 40_000_000)
  let oldAccount = Task { await refresh.loadThread(threadId: 34, token: "a") }
  await entered(target); TokenStore.shared.token = "b"; await oldAccount.value
  check(notes.notes.isEmpty, "previous token response cannot publish a read")
  TokenStore.shared.token = "a"
  target = api.calls + 1; success(delay: 40_000_000)
  let changedID = Task { await refresh.loadThread(threadId: 34, token: "a") }
  await entered(target); UserDefaults.standard.set(2, forKey: key); await changedID.value
  check(notes.notes.isEmpty, "account-ID change cannot publish the old account read")
  UserDefaults.standard.set(1, forKey: key)
  target = api.calls + 1; success(delay: 40_000_000)
  let old = Task { await refresh.loadThread(threadId: 34, token: "a") }
  await entered(target); success(); await refresh.loadThread(threadId: 34, token: "a"); await old.value
  check(notes.notes.count == 1, "superseded response cannot publish a second stale read")
  func conversation(_ kind: String, _ id: Int, _ unread: Int) -> ConversationDTO {
   .init(kind:kind,id:id,title:"QA",displayName:"Saved alias",updatedAt:"2026-10-20",isGroup:false,phone:"+15551234567",unreadCount:unread,avatarUsers:nil,last:.init(text:"Test",messageId:80,at:"2026-10-20",hasMedia:false,mediaCount:0,mediaKinds:nil,thumbUrl:nil,senderName:nil))
  }
  let list = ListQA()
  list.conversations = [conversation("sms",34,1),conversation("chat",34,4),conversation("sms",35,2)]
  let before = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(list.conversations[0])) as! [String:Any]
  list.applySMSRead(threadId:34, accountId:1)
  check(list.conversations[0].unreadCount == 0, "confirmed SMS read immediately clears its Chats badge")
  check(list.conversations[1].unreadCount == 4 && list.conversations[2].unreadCount == 2, "same-numbered Chatforia room and other SMS thread remain untouched")
  var expected = before; expected["unreadCount"] = 0
  let after = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(list.conversations[0])) as! [String:Any]
  check(NSDictionary(dictionary:expected).isEqual(to:after), "read preserves every conversation field except unread count")
  check(list.conversationLoadVersion == 1 && list.refreshes == 1, "list response version invalidates before reconciliation")
  list.applySMSRead(threadId:34, accountId:1)
  check(list.refreshes == 1, "repeated polling read does not schedule another list fetch")
  list.applySMSRead(threadId:35, accountId:2)
  check(list.conversations[2].unreadCount == 2, "another account read cannot clear the current row")
  list.applySMSRead(threadId:999, accountId:1)
  check(list.conversations.count == 3 && list.refreshes == 1, "unknown thread cannot create a conversation")
  print("\(count) native SMS unread checks passed")
 }
}
'''
dto = (src / 'ConversationDTO.swift').read_text()
code = STUBS + load + '\n}\n' + dto + '''
@MainActor final class ListQA {
 var conversations: [ConversationDTO] = []
 var conversationLoadVersion = 0
 var refreshes = 0
 func scheduleLiveRefresh() { conversationLoadVersion += 1; refreshes += 1 }
''' + apply + '\n}\n' + HARNESS
compiler = shutil.which('swiftc')
if not compiler: raise SystemExit('Run this native harness on the Mac with Xcode installed (swiftc required).')
with tempfile.TemporaryDirectory(prefix='sms-unread-qa-') as tmp:
    swift = Path(tmp) / 'SMSUnreadQA.swift'; binary = Path(tmp) / 'SMSUnreadQA'
    swift.write_text(code)
    subprocess.run([compiler,'-parse-as-library',str(swift),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
