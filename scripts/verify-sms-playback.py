#!/usr/bin/env python3
"""Compile the actual SMS playback controller with deterministic platform fixtures.
Run on macOS. Device QA still verifies audio decoding, routing and audible playback.
"""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
view=(root/'Chatforia/Chatforia/SMSThreadView.swift').read_text()
start=view.index('@MainActor\nprivate final class SMSAttachmentPlayback:')
end=view.index('// Isolated from the Chatforia recorder',start)
controller=view[start:end].replace('private final class SMSAttachmentPlayback','final class SMSAttachmentPlayback').replace('@Published ','').replace('AVAudioSession','QAAudioSession').replace('AVAudioPlayer','QAAudioPlayer')
assert 'import Combine' in view
card=view[view.index('private struct SMSAudioAttachmentCard:'):start]
assert 'playback.identity == identity' in card
assert 'active && playback.isPlaying' in card
assert 'playback.stop(ifIdentity: identity)' in card
assert 'AVAudioPlayer(data: data)' in view[start:end]
assert 'AudioPlaybackViewModel' not in view[start:end]
print('PASS: SMS-only byte playback and per-message card state are wired',flush=True)
if '--wiring-only' in sys.argv:raise SystemExit(0)
STUBS=r'''
import Foundation
protocol ObservableObject:AnyObject {}
final class TokenStore {static let shared=TokenStore();var token:String?="a";func read()->String?{token}}
enum HTTPMethod {case GET}
struct APIRequest {let path:String;let method:HTTPMethod;let requiresAuth:Bool}
struct QAResponse {let statusCode:Int}
final class APIClient {
 static let shared=APIClient();var calls=0;var delay:UInt64=0;var path="";var status=200;var data=Data([1]);var failure=false
 func sendRaw(_ request:APIRequest,token:String)async throws ->(Data,QAResponse){
  calls+=1;path=request.path
  let saved=data,code=status,fail=failure
  if delay>0 {try? await Task.sleep(nanoseconds:delay)}
  if fail {throw URLError(.notConnectedToInternet)}
  return(saved,QAResponse(statusCode:code))
 }
}
final class QAAudioPlayer {
 static var canPlay=true;static var instances=[QAAudioPlayer]()
 var isPlaying=false;var currentTime:Double=0;let duration:Double=2
 init(data:Data)throws {if data != Data([1]) {throw URLError(.cannotDecodeContentData)};Self.instances.append(self)}
 func prepareToPlay()->Bool{true}
 func play()->Bool{isPlaying=Self.canPlay;return isPlaying}
 func pause(){isPlaying=false}
 func stop(){isPlaying=false}
}
final class QAAudioSession {
 enum Category{case playback};enum Mode{case `default`}
 struct Options:OptionSet{let rawValue:Int;static let notifyOthersOnDeactivation=Options(rawValue:1)}
 static let instance=QAAudioSession();var activations=0;var deactivations=0
 static func sharedInstance()->QAAudioSession{instance}
 func setCategory(_ value:Category,mode:Mode)throws{}
 func setActive(_ value:Bool,options:Options=[])throws{if value{activations+=1}else{deactivations+=1}}
}
'''
HARNESS=r'''
import Foundation
@main struct SMSPlaybackQA {
 @MainActor static func main()async {
  let p=SMSAttachmentPlayback.shared,api=APIClient.shared
  var checks=0
  func check(_ ok:Bool,_ label:String){precondition(ok,label);checks+=1;print("PASS: \(label)")}
  func settle()async {try? await Task.sleep(nanoseconds:40_000_000)}
  func play(_ id:String="a:166:0",_ token:String?="a"){p.toggle(identity:id,messageID:166,mediaIndex:0,token:token)}
  p.stop();check(QAAudioSession.instance.deactivations==0,"idle cleanup cannot deactivate another audio session")
  play("a:166:0",nil);check(api.calls==0 && p.errorText != nil && !p.isPlaying,"signed-out playback fails visibly without fetching")
  play();await settle()
  check(api.path=="sms/media/166/0" && p.isPlaying && p.duration==2,"authorized endpoint bytes create a ready playing SMS player")
  let first=QAAudioPlayer.instances.last!
  play();check(!p.isPlaying && !first.isPlaying,"same card pauses its own player")
  play();check(p.isPlaying && api.calls==1,"same card resumes without downloading again")
  play("a:167:0");await settle()
  check(p.identity=="a:167:0" && p.isPlaying && !first.isPlaying,"another card stops the prior player and owns the active state")
  p.stop(ifIdentity:"a:166:0");check(p.identity=="a:167:0" && p.isPlaying,"removing an inactive row cannot stop another card")
  p.stop(ifIdentity:"a:167:0");check(p.identity==nil && !p.isPlaying,"removing the active row stops playback")
  api.delay=100_000_000;let before=api.calls;play();play();await settle()
  check(api.calls==before+1 && p.isLoading,"repeated loading taps cannot duplicate the download")
  p.stop();try? await Task.sleep(nanoseconds:130_000_000)
  check(p.identity==nil && !p.isPlaying,"late download cannot restart a dismissed player")
  play();await settle();TokenStore.shared.token="b"
  try? await Task.sleep(nanoseconds:130_000_000)
  check(p.identity==nil && !p.isPlaying,"account change during download prevents stale playback")
  TokenStore.shared.token="a";api.delay=0;api.data=Data([9]);play();await settle()
  check(p.errorText != nil && !p.isPlaying && !p.isLoading,"undecodable bytes fail visibly instead of falsely showing Playing")
  api.data=Data([1]);play();await settle();check(p.isPlaying && p.errorText==nil,"explicit retry can recover after invalid media")
  p.stop();api.status=403;play();await settle()
  check(p.errorText != nil && !p.isPlaying,"non-success response cannot play as audio")
  api.status=200;api.failure=true;play();await settle()
  check(p.errorText != nil && !p.isLoading,"network failure releases loading state and reports a retry")
  api.failure=false;QAAudioPlayer.canPlay=false;play();await settle()
  check(p.errorText != nil && !p.isPlaying,"player start failure cannot show Playing")
  QAAudioPlayer.canPlay=true;play();check(p.isPlaying && p.errorText==nil,"explicit retry can recover a player start failure")
  QAAudioPlayer.instances.last!.isPlaying=false
  try? await Task.sleep(nanoseconds:150_000_000)
  check(!p.isPlaying,"finished playback returns its card to Play")
  p.stop();print("\(checks) SMS playback checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-sms-playback-qa-') as temp:
    temp=Path(temp)
    for name,source in [('Stubs.swift',STUBS),('Playback.swift','import Foundation\n'+controller),('Harness.swift',HARNESS)]:
        (temp/name).write_text(source)
    executable=temp/'verify'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',*map(str,sorted(temp.glob('*.swift'))),'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True)
