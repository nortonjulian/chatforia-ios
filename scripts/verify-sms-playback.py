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
assert 'playback.prefetchDuration(identity: identity' in card
assert 'playback.cancelDurationPrefetch(identity: identity)' in card
assert 'playback.cachedDuration(for: identity)' in card
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
 static var canPlay=true
 private static let instanceLock=NSLock()
 private static var storedInstances=[QAAudioPlayer]()
 static var instances:[QAAudioPlayer]{instanceLock.lock();defer{instanceLock.unlock()};return storedInstances}
 let initializedOnMainThread=Thread.isMainThread
 var prepareCalls=0;var playCalls=0
 var isPlaying=false;var currentTime:Double=0;let duration:Double=2
 init(data:Data)throws {if data != Data([1]) {throw URLError(.cannotDecodeContentData)};Self.instanceLock.lock();Self.storedInstances.append(self);Self.instanceLock.unlock()}
 func prepareToPlay()->Bool{prepareCalls+=1;return true}
 func play()->Bool{playCalls+=1;isPlaying=Self.canPlay;return isPlaying}
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
  func fresh(){p.stop();p.prefetchDuration(identity:"reset",messageID:0,mediaIndex:0,token:nil)}
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
  fresh();api.delay=100_000_000;let before=api.calls;play();play();await settle()
  check(api.calls==before+1 && p.isLoading,"repeated loading taps cannot duplicate the download")
  p.stop();try? await Task.sleep(nanoseconds:130_000_000)
  check(p.identity==nil && !p.isPlaying,"late download cannot restart a dismissed player")
  play();await settle();TokenStore.shared.token="b"
  try? await Task.sleep(nanoseconds:130_000_000)
  check(p.identity==nil && !p.isPlaying,"account change during download prevents stale playback")
  TokenStore.shared.token="a";api.delay=0;api.data=Data([9]);play();await settle()
  check(p.errorText != nil && !p.isPlaying && !p.isLoading,"undecodable bytes fail visibly instead of falsely showing Playing")
  api.data=Data([1]);play();await settle();check(p.isPlaying && p.errorText==nil,"explicit retry can recover after invalid media")
  fresh();api.status=403;play();await settle()
  check(p.errorText != nil && !p.isPlaying,"non-success response cannot play as audio")
  api.status=200;api.failure=true;play();await settle()
  check(p.errorText != nil && !p.isLoading,"network failure releases loading state and reports a retry")
  api.failure=false;QAAudioPlayer.canPlay=false;play();await settle()
  check(p.errorText != nil && !p.isPlaying,"player start failure cannot show Playing")
  QAAudioPlayer.canPlay=true;play();check(p.isPlaying && p.errorText==nil,"explicit retry can recover a player start failure")
  QAAudioPlayer.instances.last!.isPlaying=false
  try? await Task.sleep(nanoseconds:150_000_000)
  check(!p.isPlaying,"finished playback returns its card to Play")
  p.stop();await settle()
  api.delay=0;api.failure=false;api.status=200;api.data=Data([1]);TokenStore.shared.token="a"
  let q=SMSAttachmentPlayback()
  let activations=QAAudioSession.instance.activations,deactivations=QAAudioSession.instance.deactivations
  let inspectStart=QAAudioPlayer.instances.count,fetchStart=api.calls
  q.prefetchDuration(identity:"a:201:0",messageID:201,mediaIndex:0,token:"a")
  await settle()
  check(q.cachedDuration(for:"a:201:0")==2 && q.identity==nil && !q.isPlaying,"visible SMS learns actual duration before Play")
  let inspectors=Array(QAAudioPlayer.instances.dropFirst(inspectStart))
  check(!inspectors.isEmpty && inspectors.allSatisfy{!$0.initializedOnMainThread && $0.prepareCalls==0 && $0.playCalls==0},"quiet inspection runs off the main thread without preparing or playing")
  check(QAAudioSession.instance.activations==activations && QAAudioSession.instance.deactivations==deactivations,"quiet lookup never activates or deactivates the audio session")
  q.prefetchDuration(identity:"a:201:0",messageID:201,mediaIndex:0,token:"a");await settle()
  check(api.calls==fetchStart+1,"duplicate metadata requests reuse the cached duration")
  q.toggle(identity:"a:201:0",messageID:201,mediaIndex:0,token:"a");await settle()
  check(q.isPlaying && api.calls==fetchStart+1,"Play reuses inspected bytes without another download")
  api.delay=100_000_000;let pendingStart=api.calls
  q.prefetchDuration(identity:"a:202:0",messageID:202,mediaIndex:0,token:"a");await settle()
  q.toggle(identity:"a:202:0",messageID:202,mediaIndex:0,token:"a")
  try? await Task.sleep(nanoseconds:130_000_000)
  check(q.isPlaying && q.identity=="a:202:0" && api.calls==pendingStart+1,"Play shares an in-flight duration lookup")
  api.delay=0
  let playing=QAAudioPlayer.instances.last!,activeBefore=QAAudioSession.instance.activations
  q.prefetchDuration(identity:"a:203:0",messageID:203,mediaIndex:0,token:"a");await settle()
  check(q.identity=="a:202:0" && q.isPlaying && playing.isPlaying && QAAudioSession.instance.activations==activeBefore,"another row's duration lookup cannot interrupt playback")
  q.stop();api.delay=100_000_000
  q.prefetchDuration(identity:"a:204:0",messageID:204,mediaIndex:0,token:"a");await settle()
  q.cancelDurationPrefetch(identity:"a:204:0")
  try? await Task.sleep(nanoseconds:130_000_000)
  check(q.cachedDuration(for:"a:204:0")==nil && !q.isPlaying,"leaving a row cancels quiet work and rejects late results")
  q.prefetchDuration(identity:"a:205:0",messageID:205,mediaIndex:0,token:"a");await settle()
  TokenStore.shared.token="b"
  q.prefetchDuration(identity:"b:205:0",messageID:205,mediaIndex:0,token:"b")
  try? await Task.sleep(nanoseconds:130_000_000)
  check(q.cachedDuration(for:"a:205:0")==nil && q.cachedDuration(for:"b:205:0")==2 && q.cachedDuration(for:"a:201:0")==nil,"account change clears metadata and rejects old-account delivery")
  q.prefetchDuration(identity:"reset",messageID:0,mediaIndex:0,token:nil)
  let signedOutCalls=api.calls
  q.prefetchDuration(identity:"invalid",messageID:0,mediaIndex:-1,token:nil);await settle()
  check(api.calls==signedOutCalls,"signed-out metadata request never fetches")
  TokenStore.shared.token="a";api.delay=0;api.failure=true
  q.prefetchDuration(identity:"a:206:0",messageID:206,mediaIndex:0,token:"a");await settle()
  check(q.cachedDuration(for:"a:206:0")==nil && q.errorText==nil && !q.isPlaying,"quiet fetch failure never shows a playback error or fabricates duration")
  api.failure=false;q.toggle(identity:"a:206:0",messageID:206,mediaIndex:0,token:"a");await settle()
  check(q.isPlaying && q.duration==2,"explicit Play recovers after failed duration inspection")
  q.stop();api.data=Data([9])
  q.prefetchDuration(identity:"a:207:0",messageID:207,mediaIndex:0,token:"a");await settle()
  check(q.cachedDuration(for:"a:207:0")==nil,"undecodable media never creates duration metadata")
  q.prefetchDuration(identity:"reset",messageID:0,mediaIndex:0,token:nil)
  api.data=Data([1]);api.delay=100_000_000;let queueStart=api.calls
  for id in 300...304{q.prefetchDuration(identity:"a:\(id):0",messageID:id,mediaIndex:0,token:"a")}
  await settle();check(api.calls==queueStart+2,"visible-row metadata work is bounded to two concurrent fetches")
  try? await Task.sleep(nanoseconds:350_000_000)
  check((300...304).allSatisfy{q.cachedDuration(for:"a:\($0):0")==2},"bounded queue eventually populates every visible duration")
  q.prefetchDuration(identity:"reset",messageID:0,mediaIndex:0,token:nil)
  api.delay=100_000_000
  let priorityStart=api.calls
  q.prefetchDuration(identity:"a:401:0",messageID:401,mediaIndex:0,token:"a")
  q.prefetchDuration(identity:"a:402:0",messageID:402,mediaIndex:0,token:"a")
  await settle();q.toggle(identity:"a:403:0",messageID:403,mediaIndex:0,token:"a")
  try? await Task.sleep(nanoseconds:250_000_000)
  check(q.isPlaying && q.identity=="a:403:0" && q.cachedDuration(for:"a:401:0")==2 && q.cachedDuration(for:"a:402:0")==2 && api.calls>=priorityStart+3,"explicit Play takes priority and preempted visible durations recover")
  q.stop();q.prefetchDuration(identity:"reset",messageID:0,mediaIndex:0,token:nil)
  let invalidStart=api.calls
  q.prefetchDuration(identity:"invalid",messageID:0,mediaIndex:-1,token:"a");await settle()
  check(api.calls==invalidStart,"invalid message and attachment identifiers cannot start metadata requests")
  api.status=403
  q.prefetchDuration(identity:"a:501:0",messageID:501,mediaIndex:0,token:"a");await settle()
  try? await Task.sleep(nanoseconds:130_000_000)
  check(q.cachedDuration(for:"a:501:0")==nil && q.errorText==nil,"unauthorized media cannot disclose cached duration or disrupt playback UI")
  q.prefetchDuration(identity:"reset",messageID:0,mediaIndex:0,token:nil)
  api.status=200;api.delay=0
  print("\(checks) SMS playback and duration checks passed")
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
