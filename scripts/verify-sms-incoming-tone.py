#!/usr/bin/env python3
"""Compile the actual SMS gate with Foundation; no app, network or audio required."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Chatforia/Chatforia/SocketManager.swift').read_text()
gate = source[source.index('struct IncomingSMSToneGate {'):]
callback = source[source.index('socket.on("sms:message:new")'):source.index('// DISCONNECT')]
assert 'incomingSMSTones.claim(' in callback
assert 'suppressed: shouldSuppressTone' in callback
assert 'if let senderId, senderId != currentUserId' not in callback
assert 'name: .socketSMSMessageNew' in callback
print('PASS: SMS sound gate and existing history notification are wired', flush=True)
harness = r'''
@main struct SMSIncomingToneQA {
    static var checks = 0
    static func check(_ ok: Bool, _ label: String) {
        guard ok else { fatalError("FAIL: " + label) }
        checks += 1
        print("PASS: " + label)
    }
    static func row(_ id: Any = 7, direction: String = "in", thread: Any = 34) -> [String: Any] {
        ["threadId": 34, "message": ["id": id, "threadId": thread, "direction": direction]]
    }
    static func main() {
        var gate = IncomingSMSToneGate()
        check(gate.claim(payload: row(), userId: 1, suppressed: false), "inbound carrier SMS sounds without a sender ID")
        check(!gate.claim(payload: row(), userId: 1, suppressed: false), "duplicate delivery stays quiet")
        check(!gate.claim(payload: row(8, direction: "out"), userId: 1, suppressed: false), "outgoing SMS stays quiet")
        check(gate.claim(payload: row(8), userId: 1, suppressed: false), "next inbound message remains eligible")
        check(!gate.claim(payload: row(9), userId: 1, suppressed: true), "reconnect suppression is respected")
        check(!gate.claim(payload: row(9), userId: 1, suppressed: false), "suppressed duplicate cannot chime later")
        check(!gate.claim(payload: row(10), userId: 0, suppressed: false), "signed-out events cannot chime")
        check(gate.claim(payload: row(), userId: 2, suppressed: false), "accounts have independent message identity")
        check(!gate.claim(payload: row(11, thread: 35), userId: 1, suppressed: false), "mismatched thread is rejected")
        check(!gate.claim(payload: [:], userId: 1, suppressed: false), "malformed payload stays quiet")
        for invalid in ([0, -1, 1.5, true, "bad", "0", NSNull()] as [Any]) {
            check(!gate.claim(payload: row(invalid), userId: 1, suppressed: false), "invalid message identity rejected: \(invalid)")
        }
        let strings: [String: Any] = ["threadId": "34", "message": ["id": "12", "threadId": "34", "direction": "in"]]
        check(gate.claim(payload: strings, userId: 1, suppressed: false), "string identifiers remain supported")
        let json = try! JSONSerialization.jsonObject(with: Data(#"{"threadId":34,"message":{"id":13,"threadId":34,"direction":"in"}}"#.utf8)) as! [String: Any]
        check(gate.claim(payload: json, userId: 1, suppressed: false), "real JSON number identities are accepted")
        var bounded = IncomingSMSToneGate()
        for id in 1...513 { _ = bounded.claim(payload: row(id), userId: 1, suppressed: false) }
        check(!bounded.claim(payload: row(513), userId: 1, suppressed: false), "recent messages remain deduplicated after ledger fills")
        print("\(checks) native SMS tone checks passed")
    }
}
'''
compiler = shutil.which('swiftc')
if not compiler:
    raise SystemExit('Swift compiler required. Run this verification on the Mac with Xcode installed.')
with tempfile.TemporaryDirectory(prefix='sms-tone-qa-') as tmp:
    swift = Path(tmp) / 'SMSIncomingToneQA.swift'
    binary = Path(tmp) / 'SMSIncomingToneQA'
    swift.write_text('import Foundation\n' + gate + '\n' + harness)
    subprocess.run([compiler, '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
