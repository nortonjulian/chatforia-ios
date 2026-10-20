#!/usr/bin/env python3
"""Compile actual SMS refresh and chat subtitle methods with deterministic fixtures.
Run on macOS; the Xcode app build and physical refresh checks remain separate.
"""
from pathlib import Path
import json, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
src = root / 'Chatforia/Chatforia'
vm = (src / 'SMSThreadViewModel.swift').read_text()
view = (src / 'ChatsRootView.swift').read_text()
refresh = vm[vm.index('    func loadThread('):vm.index('    func sendTextMessage(')]
subtitle = view[view.index('    private func conversationSubtitle('):view.index('    private func conversationTimestamp(')]
assert 'requestVersion == refreshVersion' in refresh
assert 'TokenStore.shared.read() == token' in refresh
assert '!isCancelledRefresh(error)' in refresh
assert 'case .network(let underlying)' in refresh
assert 'errorText = nil' in refresh[refresh.index('thread = fetched'):]
assert 'caseInsensitiveCompare("[voice note]")' in subtitle
assert 'sms.voiceNote' in subtitle
assert 'voiceNoteLabel.isEmpty || voiceNoteLabel == "sms.voiceNote" ? "Voice note"' in subtitle
assert 'return "\\(sender): \\(text)"' in subtitle
catalog = json.loads((src / 'Localizable.xcstrings').read_text())
assert catalog['strings']['sms.voiceNote']['localizations']['en']['stringUnit']['value'] == 'Voice note'
print('PASS: scoped cancellation, latest-response guards and display-only localized labels are wired', flush=True)
if '--wiring-only' in sys.argv:
    raise SystemExit(0)
STUBS = r'''
import Foundation
struct SMSMessageDTO: Decodable, Equatable { let id: Int }
struct SMSThreadDTO: Decodable { let id: Int; let sortedMessages: [SMSMessageDTO] }
struct APIRequest { let path: String; let method: HTTPMethod; let requiresAuth: Bool }
enum HTTPMethod { case GET }
enum APIError: Error { case network(Error); case server; case decoding(Error) }
@MainActor final class TokenStore {
 static let shared = TokenStore(); var token: String? = "a"
 func read() -> String? { token }
}
@MainActor final class NotificationCoordinator {
 static let shared = NotificationCoordinator(); var calls = 0
 func refreshBadgeState() async { calls += 1 }
}
@MainActor final class APIClient {
 struct Plan { let result: Result<SMSThreadDTO, Error>; let delay: UInt64 }
 static let shared = APIClient(); var plans: [Plan] = []; var calls = 0
 func send<T: Decodable>(_ request: APIRequest, token: String) async throws -> T {
  precondition(!plans.isEmpty); calls += 1
  let plan = plans.removeFirst()
  if plan.delay > 0 { try? await Task.sleep(nanoseconds: plan.delay) }
  return try plan.result.get() as! T
 }
}
var qaVoiceNoteOverride: String?
func appText(_ key: String, languageCode: String) -> String {
 if key == "sms.voiceNote", let override = qaVoiceNoteOverride { return override }
 if key == "sms.voiceNote" { return languageCode == "es" ? "Nota de voz" : "Voice note" }
 return key
}
@MainActor final class RefreshQA {
 var thread: SMSThreadDTO?; var messages: [SMSMessageDTO] = []
 var isLoading = false; var errorText: String?; var refreshVersion = 0
 var appLanguage = "en"
 func friendlyErrorMessage(_ error: Error) -> String { "Visible failure" }
'''
HARNESS = r'''
@main struct QA {
 @MainActor static func main() async {
  let api = APIClient.shared
  var count = 0
  func check(_ value: Bool, _ label: String) {
   precondition(value, label); count += 1; print("PASS: \(label)")
  }
  func success(_ id: Int, thread: Int = 67, delay: UInt64 = 0) {
   api.plans.append(.init(result: .success(.init(id: thread, sortedMessages: [.init(id: id)])), delay: delay))
  }
  func failure(_ error: Error, delay: UInt64 = 0) {
   api.plans.append(.init(result: .failure(error), delay: delay))
  }
  func entered(_ calls: Int) async { while api.calls < calls { await Task.yield() } }
  let vm = RefreshQA()
  success(1); await vm.loadThread(threadId: 67, token: "a")
  check(vm.messages.map(\.id) == [1] && !vm.isLoading && vm.errorText == nil, "initial history loads and clears loading")
  for (label, error) in [
   ("Swift cancellation", CancellationError() as Error),
   ("URL cancellation", URLError(.cancelled) as Error),
   ("NSError cancellation", NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled) as Error),
   ("wrapped URL cancellation", APIError.network(URLError(.cancelled)) as Error),
   ("nested cancellation", APIError.network(APIError.network(CancellationError())) as Error)
  ] {
   failure(error); await vm.loadThread(threadId: 67, token: "a")
   check(vm.errorText == nil && vm.messages.map(\.id) == [1] && !vm.isLoading, "\(label) preserves history without a false failure banner")
  }
  failure(APIError.network(URLError(.notConnectedToInternet)))
  await vm.loadThread(threadId: 67, token: "a")
  check(vm.errorText == "sms.refreshFailed" && vm.messages.map(\.id) == [1], "genuine network failure stays visible and preserves loaded messages")
  success(2); await vm.loadThread(threadId: 67, token: "a")
  check(vm.errorText == nil && vm.messages.map(\.id) == [2], "successful retry clears the failure banner")
  let empty = RefreshQA(); failure(APIError.server)
  await empty.loadThread(threadId: 67, token: "a")
  check(empty.errorText == "Visible failure" && !empty.isLoading, "first-load server failure stays visible")
  failure(NSError(domain: "OtherDomain", code: NSURLErrorCancelled))
  await vm.loadThread(threadId: 67, token: "a")
  check(vm.errorText != nil, "unrelated error with the same numeric code is not hidden")
  var target = api.calls + 1
  failure(APIError.server, delay: 80_000_000)
  let oldFailure = Task { await vm.loadThread(threadId: 67, token: "a") }
  await entered(target); success(3); await vm.loadThread(threadId: 67, token: "a"); await oldFailure.value
  check(vm.errorText == nil && vm.messages.map(\.id) == [3], "late old failure cannot restore a banner after newer success")
  target = api.calls + 1; success(4, delay: 80_000_000)
  let oldSuccess = Task { await vm.loadThread(threadId: 67, token: "a") }
  await entered(target); success(5); await vm.loadThread(threadId: 67, token: "a"); await oldSuccess.value
  check(vm.messages.map(\.id) == [5], "late old history cannot replace the latest refresh")
  target = api.calls + 1; success(6, delay: 30_000_000)
  let old = Task { await empty.loadThread(threadId: 67, token: "a") }
  await entered(target); success(7, delay: 120_000_000)
  let latest = Task { await empty.loadThread(threadId: 67, token: "a") }
  await entered(target + 1); await old.value
  check(empty.isLoading, "old completion cannot clear the current loading indicator")
  await latest.value; check(!empty.isLoading && empty.messages.map(\.id) == [7], "current refresh finishes loading normally")
  target = api.calls + 1; success(8, delay: 80_000_000)
  let cancelled = Task { await vm.loadThread(threadId: 67, token: "a") }
  await entered(target); cancelled.cancel(); await cancelled.value
  check(vm.messages.map(\.id) == [5] && vm.errorText == nil, "cancelled task cannot publish a successful late response")
  target = api.calls + 1; success(9, delay: 80_000_000)
  let previousAccount = Task { await vm.loadThread(threadId: 67, token: "a") }
  await entered(target); TokenStore.shared.token = "b"; await previousAccount.value
  check(vm.messages.map(\.id) == [5], "previous account response cannot overwrite current state")
  TokenStore.shared.token = "a"
  let calls = api.calls; await vm.loadThread(threadId: 67, token: nil)
  check(api.calls == calls && vm.errorText == "ios.missing_auth_token" && !vm.isLoading, "signed-out refresh cannot request private history")
  success(10, thread: 68); await vm.loadThread(threadId: 68, token: "a")
  check(vm.thread?.id == 68 && vm.messages.map(\.id) == [10], "subsequent thread refresh still loads its own history")
  func convo(_ text: String?, group: Bool = false, sender: String? = nil, audio: Bool = false, kind: String = "chat") -> ConversationDTO {
   .init(kind: kind, id: 1, title: "QA", displayName: nil, updatedAt: nil, isGroup: group, phone: nil, unreadCount: nil, avatarUsers: nil,
    last: .init(text: text, messageId: 10, at: nil, hasMedia: audio, mediaCount: audio ? 1 : nil, mediaKinds: audio ? ["AUDIO"] : nil, thumbUrl: nil, senderName: sender))
  }
  let ui = SubtitleQA(appLanguage: "en")
  check(ui.conversationSubtitle(convo("[voice note]")) == "Voice note", "direct preview removes the exact legacy marker brackets")
  check(ui.conversationSubtitle(convo(" [Voice Note] ", kind: "sms")) == "Voice note", "SMS legacy marker ignores surrounding whitespace and letter case")
  check(ui.conversationSubtitle(convo("[voice note]", group: true, sender: "Julian Norton")) == "Julian Norton: Voice note", "group preview keeps its sender and removes marker brackets")
  check(ui.conversationSubtitle(convo("[voice note]", group: true, sender: "[papi]")) == "[papi]: Voice note", "brackets in participant names stay literal")
  check(ui.conversationSubtitle(convo("I sent [voice note] yesterday")) == "I sent [voice note] yesterday", "real text containing brackets is not rewritten")
  check(ui.conversationSubtitle(convo("[test]")) == "[test]", "unrelated bracketed text stays literal")
  check(ui.conversationSubtitle(convo("Voice note")) == "Voice note", "already normalized previews remain unchanged")
  check(SubtitleQA(appLanguage: "es").conversationSubtitle(convo("[voice note]")) == "Nota de voz", "marker uses the existing localized voice-note label")
  check(ui.conversationSubtitle(convo(nil, audio: true)).contains("ios.voice_message"), "existing empty-text audio fallback is preserved")
  check(convo("[voice note]").last?.text == "[voice note]", "display formatting never mutates the stored preview")
  qaVoiceNoteOverride = "sms.voiceNote"
  check(ui.conversationSubtitle(convo("[voice note]")) == "Voice note", "unresolved translation key never appears in the direct preview")
  check(ui.conversationSubtitle(convo("[voice note]", group: true, sender: "papi")) == "papi: Voice note", "unresolved translation key never appears in the group preview")
  qaVoiceNoteOverride = "   "
  check(ui.conversationSubtitle(convo("[voice note]")) == "Voice note", "empty translation has a readable voice-note fallback")
  qaVoiceNoteOverride = nil
  print("\(count) native refresh and preview-label checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-refresh-label-qa-') as d:
    temp = Path(d)
    (temp / 'Actual.swift').write_text(STUBS + refresh + '\n}\nstruct SubtitleQA { let appLanguage: String\n' + subtitle.replace('private func conversationSubtitle', 'func conversationSubtitle') + '\n}\n' + HARNESS)
    (temp / 'ConversationDTO.swift').write_text((src / 'ConversationDTO.swift').read_text())
    executable = temp / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', *map(str, sorted(temp.glob('*.swift'))), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
