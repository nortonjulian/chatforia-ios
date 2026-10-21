#!/usr/bin/env python3
"""Exercise actual SMS voice controller and media-send method with deterministic services.
Run on macOS: preview hardware, permission UI and carrier delivery still need device QA.
"""
from pathlib import Path
import subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1]
src=root/'Chatforia/Chatforia'
view=(src/'SMSThreadView.swift').read_text()
vm=(src/'SMSThreadViewModel.swift').read_text()
controller=view[view.index('@MainActor\nfinal class SMSVoiceNoteController:'):].replace('@Published ','').replace('AVAudioSession', 'SMSVoiceQAAudioSession')
media=vm[vm.index('    func sendMediaMessage('):vm.index('    func deleteMessage(')]
assert 'onMicTap: {' in view and 'await voice.start(token:' in view
assert 'onSendVoiceDraftTap: { Task { await sendSMSVoiceDraft() } }' in view
assert 'SMSAudioAttachmentCard(message: message' in view and 'path: "sms/media/' in view
assert 'mimeType: "audio/mp4"' in controller and 'size <= 500_000' in controller
assert 'self.elapsed >= 60' in controller
assert 'voice.discard()' in view[view.index('.onDisappear'):view.index('.sheet(isPresented: $showSearchSheet)')]
assert 'newPhase == .background' in view # permission prompt inactivity must not cancel start
assert 'guard response.ok, response.threadId > 0' in media
print('PASS: SMS record/stop/cancel/preview/send, media playback and lifecycle wiring',flush=True)
if '--wiring-only' in sys.argv:raise SystemExit(0)
STUBS=r'''
import Foundation
import AVFoundation
protocol ObservableObject: AnyObject {}
// AVAudioSession is iOS-only. The Mac harness verifies controller decisions;
// actual recording, audio routing and playback remain real-device checks.
final class SMSVoiceQAAudioSession {
    enum Category { case playback }
    enum Mode { case `default` }
    struct Options: OptionSet {
        let rawValue: Int
        static let notifyOthersOnDeactivation = Options(rawValue: 1)
    }
    private static let instance = SMSVoiceQAAudioSession()
    static func sharedInstance() -> SMSVoiceQAAudioSession { instance }
    func setCategory(_ category: Category, mode: Mode) throws {}
    func setActive(_ active: Bool, options: Options = []) throws {}
}
final class TokenStore{static let shared=TokenStore();var token:String?="account-a";func read()->String?{token}}
final class AudioRecorderService {
    static var starts=0, cancels=0
    static var denied=false
    static var delay:UInt64=0
    static var stopDelay:UInt64=0,cancelDelay:UInt64=0
    private var url:URL?
    func start() async throws {
        Self.starts+=1
        if Self.delay>0{try? await Task.sleep(nanoseconds:Self.delay)}
        if Self.denied{throw URLError(.userAuthenticationRequired)}
        let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
        try Data(repeating:1,count:32).write(to:u);url=u
    }
    func stop() async ->VoiceNoteDraft?{guard let u=url else{return nil};url=nil;if Self.stopDelay>0{try? await Task.sleep(nanoseconds:Self.stopDelay)};return VoiceNoteDraft(fileURL:u,durationSec:2)}
    func cancel() async {Self.cancels+=1;if Self.cancelDelay>0{try? await Task.sleep(nanoseconds:Self.cancelDelay)};if let url{try? FileManager.default.removeItem(at:url)};url=nil}
}
struct UploadResultDTO{let ok:Bool?;let url:String}
final class UploadService{
 static let shared=UploadService();var count=0;var delay:UInt64=0;var fail=false
 var url="https://media.example/files/voice.m4a";var mime="";var name=""
 func uploadFile(data:Data,token:String,fileName:String,mimeType:String) async throws -> UploadResultDTO {
  count+=1;mime=mimeType;name=fileName
  if delay>0{try? await Task.sleep(nanoseconds:delay)}
  if fail{throw URLError(.notConnectedToInternet)}
  return UploadResultDTO(ok:true,url:url)
 }
}
struct APIRequest{let path:String;let method:Method;let body:Data?;let requiresAuth:Bool}
enum Method{case POST}
final class APIClient{
 static let shared=APIClient();var response=Data(#"{"ok":true,"threadId":67}"#.utf8);var body:Data?
 func send<T:Decodable>(_ request:APIRequest,token:String)async throws -> T{body=request.body;return try JSONDecoder().decode(T.self,from:response)}
}
final class AnalyticsManager{static let shared=AnalyticsManager();func capture(_ event:String,properties:[String:String]){}}
func appText(_ key:String,languageCode:String)->String{key}
@MainActor final class MediaVM{
 var isSending=false;var errorText:String?;var appLanguage="en";var loaded:Int?
 func loadThread(threadId:Int,token:String?)async{loaded=threadId}
 func friendlyErrorMessage(_ error:Error)->String{error.localizedDescription}
'''
HARNESS=r'''
import Foundation
@main struct SMSVoiceQA{
 @MainActor static func main()async throws{
 var count=0
 func check(_ value:Bool,_ label:String){precondition(value,label);count+=1;print("PASS: \(label)")}
 func recording()async ->SMSVoiceNoteController{
  let c=SMSVoiceNoteController();await c.start(token:"account-a");await c.stop();return c
 }
 let idle=SMSVoiceNoteController();let cancelled=AudioRecorderService.cancels;idle.discard()
 check(AudioRecorderService.cancels==cancelled,"leaving an unused SMS screen does not deactivate another audio session")
 await idle.start(token:nil);check(AudioRecorderService.starts==0 && idle.errorText != nil,"signed-out mic request is visible and never records")
 AudioRecorderService.denied=true;await idle.start(token:"account-a")
 check(!idle.isStarting && !idle.isRecording && idle.errorText != nil,"permission failure leaves no stuck recording state")
 AudioRecorderService.denied=false
 AudioRecorderService.delay=80_000_000
 let permission=Task{@MainActor in await idle.start(token:"account-a")}
 try? await Task.sleep(nanoseconds:10_000_000);idle.discard();await permission.value;try? await Task.sleep(nanoseconds:20_000_000)
 check(!idle.isRecording && !idle.isStarting && idle.draft==nil,"leaving during permission prevents a ghost recorder")
 AudioRecorderService.delay=0
 let c=SMSVoiceNoteController();await c.start(token:"account-a");let starts=AudioRecorderService.starts
 await c.start(token:"account-a");check(AudioRecorderService.starts==starts,"duplicate mic taps cannot start another recorder")
 await c.stop();check(c.draft != nil && !c.isRecording,"stop creates a previewable draft without sending")
 let file=c.draft!.fileURL
 var deliveries=0
 let failed=await c.send(token:"account-a"){_ in deliveries+=1;return false}
 check(!failed && c.draft != nil && FileManager.default.fileExists(atPath:file.path),"failed send retains the recording")
 check(c.errorText != nil && deliveries==1,"failure is visible and never retries delivery automatically")
 let uploader=UploadService.shared
 check(uploader.mime=="audio/mp4" && uploader.name.count<=20,"MMS upload uses accepted MIME and short filename")
 let uploads=uploader.count
 let sent=await c.send(token:"account-a"){_ in deliveries+=1;return true}
 check(sent && uploader.count==uploads && deliveries==2,"explicit retry reuses the same uploaded media")
 check(c.draft==nil && !FileManager.default.fileExists(atPath:file.path),"confirmed send clears draft and temporary audio")
 let large=await recording();try Data(repeating:1,count:500_001).write(to:large.draft!.fileURL)
 let beforeLarge=uploader.count
 let oversized=await large.send(token:"account-a"){_ in preconditionFailure("oversized delivery")}
 check(!oversized && uploader.count==beforeLarge && large.draft != nil,"oversized MMS audio stays local without upload or send")
 large.discard()
 let broken=await recording();uploader.fail=true
 let noNetwork=await broken.send(token:"account-a"){_ in preconditionFailure("delivery after upload failure")}
 check(!noNetwork && broken.draft != nil && !broken.isSending,"upload failure preserves draft and releases send gate")
 uploader.fail=false;broken.discard()
 let invalid=await recording();uploader.url=""
 let invalidURL=await invalid.send(token:"account-a"){_ in preconditionFailure("invalid media URL delivery")}
 check(!invalidURL && invalid.draft != nil,"empty upload URL cannot silently send")
 uploader.url="https://media.example/files/voice.m4a";invalid.discard()
 let duplicate=await recording();var duplicates=0
 let first=Task{@MainActor in await duplicate.send(token:"account-a"){_ in duplicates+=1;try? await Task.sleep(nanoseconds:60_000_000);return true}}
 try? await Task.sleep(nanoseconds:10_000_000)
 let second=await duplicate.send(token:"account-a"){_ in duplicates+=1;return true}
 _=await first.value;check(!second && duplicates==1,"repeated Send cannot duplicate an in-flight delivery")
 let account=await recording();uploader.delay=80_000_000
 let accountTask=Task{@MainActor in await account.send(token:"account-a"){_ in preconditionFailure("old account delivery")}}
 try? await Task.sleep(nanoseconds:10_000_000);TokenStore.shared.token="account-b"
 let changed=await accountTask.value;check(!changed,"account change during upload prevents delivery")
 account.discard();TokenStore.shared.token="account-a"
 let departed=await recording()
 let leave=Task{@MainActor in await departed.send(token:"account-a"){_ in preconditionFailure("delivery after departure")}}
 try? await Task.sleep(nanoseconds:10_000_000);departed.discard()
 let departedSent=await leave.value;check(!departedSent && departed.draft==nil,"leaving during upload prevents stale send and cleans draft")
 uploader.delay=0
 let cancelledDraft=await recording();let cancelledFile=cancelledDraft.draft!.fileURL;cancelledDraft.discard()
 check(!FileManager.default.fileExists(atPath:cancelledFile.path),"cancel draft removes local audio")
 let finalizing=SMSVoiceNoteController();await finalizing.start(token:"account-a")
 AudioRecorderService.stopDelay=60_000_000
 let finishing=Task{@MainActor in await finalizing.stop()}
 try? await Task.sleep(nanoseconds:10_000_000);finalizing.discard();await finishing.value
 check(finalizing.draft==nil && !finalizing.isRecording,"discard during async stop cannot restore a stale preview")
 AudioRecorderService.stopDelay=0
 let restart=SMSVoiceNoteController();await restart.start(token:"account-a")
 AudioRecorderService.cancelDelay=60_000_000;restart.discard();await restart.start(token:"account-a")
 check(restart.isRecording,"new recording waits for prior recorder cleanup")
 AudioRecorderService.cancelDelay=0;await restart.stop();restart.discard()
 let m=MediaVM();let api=APIClient.shared
 let id=await m.sendMediaMessage(existingThreadId:67,to:"+15551234567",mediaUrls:["https://media.example/files/voice.m4a"],token:"account-a")
 check(id==67 && m.loaded==67,"actual SMS media method reloads the authoritative thread after acknowledgment")
 let payload=try JSONSerialization.jsonObject(with:api.body!) as! [String:Any]
 check((payload["mediaUrls"] as? [String])?.count==1 && payload["body"]==nil,"voice sends one media URL without invented text")
 api.response=Data(#"{"ok":false,"threadId":67}"#.utf8)
 let refused=await m.sendMediaMessage(existingThreadId:67,to:"+15551234567",mediaUrls:["url"],token:"account-a")
 check(refused==nil && !m.isSending && m.errorText != nil,"negative acknowledgment cannot clear the voice draft as successful")
 api.response=Data(#"{"ok":true,"threadId":0}"#.utf8)
 let malformed=await m.sendMediaMessage(existingThreadId:67,to:"+15551234567",mediaUrls:["url"],token:"account-a")
 check(malformed==nil,"invalid acknowledged thread cannot navigate to a ghost conversation")
 print("\(count) native SMS voice checks passed")
 }
}
'''
response=view[view.index('struct SendSMSResponseDTO:'):view.index('struct SMSThreadView:')]
with tempfile.TemporaryDirectory(prefix='chatforia-sms-voice-qa-')as directory:
 temp=Path(directory)
 (temp/'ActualController.swift').write_text('import Foundation\nimport AVFoundation\n'+controller)
 (temp/'Stubs.swift').write_text(STUBS+media+'}\n'+response)
 (temp/'VoiceNoteDraft.swift').write_text((src/'VoiceNoteDraft.swift').read_text())
 (temp/'Harness.swift').write_text(HARNESS)
 binary=temp/'verify'
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',*[str(p)for p in sorted(temp.glob('*.swift'))],'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
