#!/usr/bin/env python3
"""Run the actual Swift URL parser and asynchronous load function on macOS."""
from pathlib import Path
import shutil, subprocess, tempfile, sys
root = Path(__file__).resolve().parents[1]
src = root / 'Chatforia/Chatforia'
app = (src / 'ChatforiaApp.swift').read_text()
shell = (src / 'AppShellView.swift').read_text()
history = (src / 'CallHistoryView.swift').read_text()
inbox = (src / 'VoicemailInboxView.swift').read_text()
model = (src / 'VoicemailInboxViewModel.swift').read_text()
assert app.count('if voicemailLinks.handle(url) { return }') == 2
for old in ['checkoutReturn.handleIncomingURL(url)', 'CreatorReferralStore.code(from: url)', 'inviteFlow.handleIncomingURL(url)']:
    assert app.count(old) == 2
assert '.environmentObject(voicemailLinks)' in app
assert '.onChange(of: voicemailLinks.pending, initial: true)' in shell
assert 'selectedTab = 1' in shell and 'voicemailLinks.pending = nil' in shell
assert 'selectedSegment = .voicemail' in history
assert 'voicemailLink: voicemailLink' in history
assert 'auth.currentUser?.id == accountID' in inbox and 'auth.currentToken == token' in inbox
assert '$0.id == requestedID && $0.userId == accountID' in inbox
assert 'Task.isCancelled' in model and 'loadGeneration == generation' in model
print('PASS: both URL entry points, pending sign-in, exact authenticated inbox selection and stale-response guards are wired')
if '--wiring-only' in sys.argv:
    sys.exit(0)
if not shutil.which('swift'):
    sys.exit('Swift is required for behavioral checks. Run this command on your Mac.')
parser = app[app.index('struct VoicemailLinkTarget:'):app.index('struct VoicemailLinkRequest:')]
load = model[model.index('    @discardableResult\n    func load('):model.index('    func refresh(')]
harness = r'''import Foundation
PARSER
@MainActor final class VoicemailService {
    static let shared = VoicemailService()
    var calls: [CheckedContinuation<[String], Error>] = []
    func fetchVoicemails(token: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { calls.append($0) }
    }
}
@MainActor final class LoadHarness {
    var loadGeneration = UUID()
    var isLoading = false
    var errorMessage: String?
    var voicemails: [String] = ["existing"]
LOAD
}
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    if !value() { fatalError("FAIL: " + label) }
    print("PASS: " + label)
}
Task { @MainActor in
    for host in ["chatforia.com", "www.chatforia.com"] {
        let base = "https://" + host
        check(VoicemailLinkTarget.parse(URL(string: base + "/voicemail")!) != nil, "legacy inbox on " + host)
        check(VoicemailLinkTarget.parse(URL(string: base + "/voicemail?id=cm123")!)?.voicemailID == "cm123", "specific recording on " + host)
    }
    for raw in ["https://evil.example/voicemail", "http://chatforia.com/voicemail", "https://chatforia.com:443/voicemail", "https://user@chatforia.com/voicemail", "https://chatforia.com/voicemail/other", "https://chatforia.com/voicemail#x", "https://chatforia.com/voicemail?id=", "https://chatforia.com/voicemail?id=a&id=b", "https://chatforia.com/voicemail?id=a%2Fb", "https://chatforia.com/mobile/esim/checkout-complete", "https://chatforia.com/join/test", "https://chatforia.com/voicemail?id=" + String(repeating: "a", count: 129)] {
        check(VoicemailLinkTarget.parse(URL(string: raw)!) == nil, "reject unrelated or malformed link " + raw)
    }
    let model = LoadHarness()
    let service = VoicemailService.shared
    let old = Task { await model.load(token: "old") }
    while service.calls.count < 1 { await Task.yield() }
    let newer = Task { await model.load(token: "new") }
    while service.calls.count < 2 { await Task.yield() }
    service.calls[1].resume(returning: ["new"])
    let newResult = await newer.value
    check(newResult && model.voicemails == ["new"], "latest response publishes")
    service.calls[0].resume(returning: ["old"])
    let oldResult = await old.value
    check(!oldResult && model.voicemails == ["new"], "late old response cannot overwrite new history")
    let cancelled = Task { await model.load(token: "cancel") }
    while service.calls.count < 3 { await Task.yield() }
    cancelled.cancel()
    service.calls[2].resume(returning: ["cancelled"])
    let cancelResult = await cancelled.value
    check(!cancelResult && model.voicemails == ["new"], "cancelled link cannot publish history")
    let failed = Task { await model.load(token: "fail") }
    while service.calls.count < 4 { await Task.yield() }
    service.calls[3].resume(throwing: NSError(domain: "test", code: 1))
    let failResult = await failed.value
    check(!failResult && model.voicemails == ["new"] && model.errorMessage != nil && !model.isLoading, "real failure is visible and preserves history")
    exit(0)
}
RunLoop.main.run()
'''.replace('PARSER', parser).replace('LOAD', load)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'verify.swift'
    path.write_text(harness)
    subprocess.run(['swift', str(path)], check=True, timeout=120)
