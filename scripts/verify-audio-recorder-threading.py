#!/usr/bin/env python3
"""Exercise the production recorder actor with deterministic platform fixtures on macOS.
Real microphone, audio routing and Xcode warning verification remain device checks.
"""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
src=root/'Chatforia/Chatforia'
actual=(src/'AudioRecorderService.swift').read_text()
assert 'actor AudioRecorderService {' in actual
assert '@MainActor\nactor AudioRecorderService' not in actual
assert 'guard revision == generation' in actual and 'guard ownsSession' in actual
sms=(src/'SMSThreadView.swift').read_text()
chat=(src/'ChatThreadView.swift').read_text()
assert 'await recorder.stop()' in sms and 'await recorder.cancel()' in sms
assert 'await audioRecorder.stop()' in chat and 'await audioRecorder.cancel()' in chat
assert 'await recorderCleanup?.value' in sms and 'await voiceRecorderCleanup?.value' in chat
assert 'guard revision == generation else' in sms[sms.index('    func stop() async {'):]
print('PASS: recorder isolation, awaited callers, cleanup and stale-draft guards are wired',flush=True)
if '--wiring-only' in sys.argv:raise SystemExit(0)
# Replace only hardware permission and platform types. Compile the complete
# production start/stop/cancel implementation, rather than a copy of its logic.
a=actual.index('    @MainActor\n    func requestPermissionIfNeeded()')
b=actual.index('    func start() async throws',a)
actual=actual[:a]+'''    @MainActor
    func requestPermissionIfNeeded() async -> Bool {
        await QAPermission.request()
    }

'''+actual[b:]
actual=actual.replace('import AVFoundation','').replace('AVAudioSession','QASession').replace('AVAudioRecorder','QARecorder').replace('AVAudioQuality.high.rawValue','64').replace('Int(kAudioFormatMPEG4AAC)','1')
STUBS=r'''
import Foundation
let AVFormatIDKey="format",AVSampleRateKey="rate",AVNumberOfChannelsKey="channels",AVEncoderAudioQualityKey="quality"
@MainActor enum QAPermission {
 static var allowed=true;static var delay:UInt64=0
 static func request()async -> Bool{if delay>0{try? await Task.sleep(nanoseconds:delay)};return allowed}
}
final class QASession {
 enum Category{case playAndRecord};enum Mode{case `default`}
 struct Options:OptionSet{let rawValue:Int;static let defaultToSpeaker=Options(rawValue:1);static let notifyOthersOnDeactivation=Options(rawValue:2)}
 static let shared=QASession();static var log=[String]();static var failActivation=false
 static func sharedInstance()->QASession{shared}
 func setCategory(_ c:Category,mode:Mode,options:Options)throws {precondition(!Thread.isMainThread,"category on UI thread");Self.log.append("category")}
 func setActive(_ value:Bool,options:Options=[])throws{
  precondition(!Thread.isMainThread,"session on UI thread");Self.log.append(value ? "activate":"deactivate")
  if value && Self.failActivation{throw URLError(.unknown)}
 }
}
final class QARecorder {
 static var failInit=false,failPrepare=false,failRecord=false;static var urls=[URL]()
 var currentTime:Double=2.5
 init(url:URL,settings:[String:Any])throws{
  precondition(!Thread.isMainThread,"recorder initialization on UI thread")
  if Self.failInit{throw URLError(.cannotCreateFile)}
  Self.urls.append(url);try Data([1,2,3]).write(to:url)
 }
 func prepareToRecord()->Bool{precondition(!Thread.isMainThread);return !Self.failPrepare}
 func record()->Bool{precondition(!Thread.isMainThread);QASession.log.append("record");return !Self.failRecord}
 func stop(){precondition(!Thread.isMainThread);QASession.log.append("stop")}
}
'''
HARNESS=r'''
import Foundation
@main struct RecorderQA {
 @MainActor static func main()async throws{
  var checks=0
  func check(_ ok:Bool,_ label:String){precondition(ok,label);checks+=1;print("PASS: \(label)")}
  let r=AudioRecorderService()
  await r.cancel();let empty=await r.stop()
  check(empty==nil && QASession.log.isEmpty,"idle stop and cancel cannot deactivate unrelated audio")
  QAPermission.allowed=false
  do{try await r.start();preconditionFailure("permission must fail")}catch{}
  check(QASession.log.isEmpty,"permission denial never activates or records")
  QAPermission.allowed=true;try await r.start()
  check(QASession.log==["category","activate","record"],"category, activation and recording execute in order off the main thread")
  let draft=await r.stop()
  check(draft?.durationSec==2.5 && Array(QASession.log.suffix(2))==["stop","deactivate"],"stop finishes recording and deactivates before returning preview draft")
  check(FileManager.default.fileExists(atPath:draft!.fileURL.path),"successful stop retains the recorded file")
  try? FileManager.default.removeItem(at:draft!.fileURL)
  let stoppedCount=QASession.log.count;_ = await r.stop();await r.cancel()
  check(QASession.log.count==stoppedCount,"repeated cleanup is idempotent")
  try await r.start();let cancelledURL=QARecorder.urls.last!;await r.cancel()
  check(!FileManager.default.fileExists(atPath:cancelledURL.path),"cancel finishes cleanup and removes temporary audio")
  QAPermission.delay=100_000_000
  let before=QASession.log.count
  let pending=Task{do{try await r.start();return false}catch{return true}}
  try? await Task.sleep(nanoseconds:20_000_000);await r.cancel()
  let rejected=await pending.value
  check(rejected && QASession.log.count==before,"cancellation during permission prevents ghost activation and recording")
  let first=Task{try await r.start()}
  try? await Task.sleep(nanoseconds:20_000_000)
  var duplicateRejected=false
  do{try await r.start()}catch{duplicateRejected=true}
  try await first.value;await r.cancel()
  check(duplicateRejected,"duplicate pending start cannot create a second recorder")
  QAPermission.delay=0
  QARecorder.failInit=true
  do{try await r.start();preconditionFailure("constructor must fail")}catch{}
  check(QASession.log.last=="deactivate","recorder construction failure releases the activated session")
  QARecorder.failInit=false;QARecorder.failPrepare=true
  do{try await r.start();preconditionFailure("prepare must fail")}catch{}
  let failedURL=QARecorder.urls.last!
  check(!FileManager.default.fileExists(atPath:failedURL.path) && QASession.log.last=="deactivate","prepare failure removes partial file and releases session")
  QARecorder.failPrepare=false;QARecorder.failRecord=true
  do{try await r.start();preconditionFailure("record must fail")}catch{}
  check(Array(QASession.log.suffix(2))==["stop","deactivate"],"record-start failure stops the recorder before session cleanup")
  QARecorder.failRecord=false;QASession.failActivation=true;let priorFiles=QARecorder.urls.count
  do{try await r.start();preconditionFailure("activation must fail")}catch{}
  check(QARecorder.urls.count==priorFiles,"activation failure cannot create or start a recorder")
  QASession.failActivation=false;try await r.start();let recovered=await r.stop()
  check(recovered != nil,"explicit start recovers after a failed activation")
  if let recovered{try? FileManager.default.removeItem(at:recovered.fileURL)}
  print("\(checks) recorder threading/lifecycle checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-recorder-qa-') as name:
    temp=Path(name)
    for filename,text in [('Recorder.swift',actual),('Stubs.swift',STUBS),('Harness.swift',HARNESS),('VoiceNoteDraft.swift',(src/'VoiceNoteDraft.swift').read_text())]:
        (temp/filename).write_text(text)
    binary=temp/'verify'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',*map(str,sorted(temp.glob('*.swift'))),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
