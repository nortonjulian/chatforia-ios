#!/usr/bin/env python3
"""Compile actual routing DTOs/services/VMs against a deterministic API fixture.
The fixture tests client behavior; server lookup idempotency still needs live QA.
"""
from pathlib import Path
import subprocess
import tempfile
import sys
root=Path(__file__).resolve().parents[1]
src=root/'Chatforia/Chatforia'
view=(src/'StartChatView.swift').read_text()
contacts=(src/'ContactsRootView.swift').read_text()
assert 'vm.createOrOpenExistingSMSThread()' in view
assert 'ChatRoomService.shared.startSMSThread(' in contacts
assert 'id: nil,' not in contacts[contacts.index('private func open('):contacts.index('private func handleContactAction')]
assert 'ConversationLookup.matches(item, query: query)' in (src/'ChatsViewModel.swift').read_text()
assert 'ForEach(vm.conversationResults, id: \\.uniqueId)' in view
assert '"SMS" : "Chatforia"' in view
assert 'showingTransportChoice' in contacts and 'showingTransportChoice' in view
print('PASS: Chats search, both New Chat hosts, contact lookup, and explicit transport choices are wired',flush=True)
if '--wiring-only' in sys.argv:
    raise SystemExit(0)
STUBS=r'''
import Foundation
protocol ObservableObject: AnyObject {}
func appText(_ key: String, languageCode: String) -> String { key }
func debugLog(_ args: Any...) {}
enum APIError: Error { case unauthorized }
enum HTTPMethod: Equatable { case GET, POST, PATCH, DELETE }
struct APIRequest {
    let path: String
    let method: HTTPMethod
    var body: Data? = nil
    var requiresAuth: Bool = false
}
final class TokenStore {
    static let shared=TokenStore()
    var token: String?="account-a"
    func read() -> String? {token}
}
final class APIClient {
    static let shared=APIClient()
    var responses:[String:Data]=[:]
    var delays:[String:UInt64]=[:]
    var calls:[(APIRequest,String?)]=[]
    func send<T:Decodable>(_ request:APIRequest, token:String?) async throws -> T {
        calls.append((request,token))
        let key=request.path.hasPrefix("conversations?") ? "conversations" : request.path
        guard let data=responses[key] else {throw APIError.unauthorized}
        let delay=delays[key] ?? 0
        if delay>0 { try? await Task.sleep(nanoseconds:delay) }
        return try JSONDecoder().decode(T.self,from:data)
    }
    func reset(){responses=[:];delays=[:];calls=[]}
}
extension Notification.Name {static let callHistoryShouldRefresh=Notification.Name("history")}
final class ContactsService {
    static let shared=ContactsService()
    func fetchContacts(query:String,token:String) async throws -> ContactsResponseDTO {throw APIError.unauthorized}
    func deleteContact(contactId:Int,token:String) async throws {}
    func updateContact(contact:ContactDTO,alias:String?,externalName:String?,favorite:Bool?,token:String) async throws -> ContactDTO {contact}
}
'''
HARNESS=r'''
import Foundation
@main struct RoutingQA {
    @MainActor static func main() async throws {
        var count=0
        func check(_ value:Bool,_ label:String){precondition(value,label);count+=1;print("PASS: \(label)")}
        func row(_ kind:String,_ id:Int?,phone:String?=nil,title:String="Regina",users:[ConversationAvatarUserDTO]?=nil)->ConversationDTO{
            ConversationDTO(kind:kind,id:id,title:title,displayName:title,updatedAt:nil,isGroup:false,
                phone:phone,unreadCount:1,avatarUsers:users,
                last:ConversationLastDTO(text:"existing history",messageId:100,at:nil,hasMedia:nil,
                    mediaCount:nil,mediaKinds:nil,thumbUrl:nil,senderName:nil))
        }
        for phone in ["+15551234567","5551234567","1 (555) 123-4567","+1 555.123.4567","0015551234567"] {
            check(ConversationLookup.normalizePhone(phone)=="+15551234567","normalizes \(phone)")
        }
        for invalid in ["", "regina1234567", "+0 5551234567", "123", "1+5551234567", "++15551234567", "+1234567890123456"] {
            check(ConversationLookup.normalizePhone(invalid)==nil,"rejects invalid phone \(invalid)")
        }
        let sms=row("sms",67,phone:"+15551234567",title:"Saved alias")
        let app=row("chat",84,users:[ConversationAvatarUserDTO(id:65,username:"regina",displayName:"Regina McFadden",avatarUrl:nil)])
        for query in ["5551234567","(555) 123-4567","+1 (555) 123-4567","123-4567"] {
            check(ConversationLookup.matches(sms,query:query),"existing number is searchable without a contact: \(query)")
        }
        check(ConversationLookup.matches(app,query:"regina"),"username remains searchable behind a saved alias")
        check(ConversationLookup.matches(app,query:"McFadden"),"participant display name is searchable")
        check(!ConversationLookup.matches(sms,query:"+44 5551234567"),"another country code does not identify this number")
        let api=APIClient.shared
        api.responses["sms/threads/start"]=Data(#"{"id":67,"contactPhone":"+15551234567","displayName":"Regina"}"#.utf8)
        let first=try await ChatRoomService.shared.startSMSThread(phone:"(555) 123-4567",token:"account-a")
        check(first.id==67 && first.kind=="sms","phone entry returns authoritative thread id, never an empty draft")
        let body=try JSONSerialization.jsonObject(with:api.calls.last!.0.body!) as! [String:Any]
        check(body["phone"] as? String == "+15551234567","phone lookup sends normalized identity to server")
        check(api.calls.last!.1=="account-a" && api.calls.last!.0.requiresAuth,"lookup uses the authenticated account")
        let second=try await ChatRoomService.shared.startSMSThread(phone:"+1 555-123-4567",contactId:9,displayName:"My alias",token:"account-a")
        check(second.id==first.id && second.title=="My alias","contact and unsaved phone paths reuse server id and preserve alias")
        var rejected=false
        do{_ = try await ChatRoomService.shared.startSMSThread(phone:"bad",token:"account-a")}catch{rejected=true}
        check(rejected && api.calls.count==2,"invalid identity cannot make a start request")
        api.responses["sms/threads/start"]=Data(#"{"id":0}"#.utf8)
        rejected=false
        do{_ = try await ChatRoomService.shared.startSMSThread(phone:"5551234567",token:"account-a")}catch{rejected=true}
        check(rejected,"malformed lookup response cannot navigate to a draft")
        api.responses["sms/threads/start"]=Data(#"{"id":67,"contactPhone":"+15551234567"}"#.utf8)
        api.responses["chatrooms/direct/65"]=Data(#"{"id":84,"isGroup":false,"participants":[{"userId":1,"user":{"id":1,"username":"julian"}},{"userId":65,"user":{"id":65,"username":"regina"}}]}"#.utf8)
        let room=try await ChatRoomService.shared.startDirectChat(userId:65,token:"account-a")
        check(room.id==84 && room.name=="regina","direct lookup preserves returned room and names the counterpart")
        let named=try await ChatRoomService.shared.startDirectChat(userId:65,token:"account-a",displayName:"Regina McFadden")
        check(named.name=="Regina McFadden","saved contact name is retained on direct entry")
        let vm=StartChatViewModel()
        vm.searchText="5551234567"
        if case .sms(let destination) = try await vm.createOrOpenExistingSMSThread(){
            check(destination.id==67,"New Chat phone action returns existing SMS history id")
        }else{preconditionFailure("wrong transport")}
        let contact=ContactSearchResultDTO(id:9,alias:"Alias",favorite:nil,externalPhone:"5551234567",externalName:nil,createdAt:nil,userId:nil,user:nil)
        if case .sms(let destination) = try await vm.destinationForContactResult(contact){
            check(destination.id==67,"New Chat saved phone contact returns same id")
        }else{preconditionFailure("wrong transport")}
        struct Envelope:Encodable{let items:[ConversationDTO]}
        api.responses["conversations"]=try JSONEncoder().encode(Envelope(items:[sms,app]))
        api.calls=[]
        await vm.searchExistingConversations(query:"Regina")
        check(vm.conversationResults.count==1 && vm.conversationResults[0].kind=="chat","search uses actual metadata, never guesses identity from an alias")
        api.responses["conversations"]=try JSONEncoder().encode(Envelope(items:[row("sms",67,phone:"+15551234567"),app]))
        await vm.searchExistingConversations(query:"Regina")
        check(vm.conversationResults.count==2,"existing app and SMS conversations remain separate choices")
        check(api.calls.allSatisfy{$0.0.method == .GET},"typing and searching never create a conversation")
        if case .sms(let destination)=try vm.destinationForExistingConversation(vm.conversationResults[0]){
            check(destination.id==67 && destination.last?.messageId==100,"selecting history preserves thread identity and metadata")
        }else{preconditionFailure("wrong transport")}
        TokenStore.shared.token="account-b"
        rejected=false
        do{_ = try vm.destinationForExistingConversation(vm.conversationResults[0])}catch{rejected=true}
        check(rejected,"previous account results cannot be selected after account change")
        TokenStore.shared.token="account-a"
        api.delays["conversations"]=100_000_000
        vm.searchText="Regina"
        let late=Task{@MainActor in await vm.searchExistingConversations(query:"Regina")}
        try? await Task.sleep(nanoseconds:20_000_000)
        vm.searchText=""
        vm.handleSearchTextChanged(currentUserId:1)
        await late.value
        check(vm.conversationResults.isEmpty,"clearing/changing query rejects late search results")
        vm.isGroupMode=true
        api.calls=[]
        await vm.searchExistingConversations(query:"Regina")
        check(api.calls.isEmpty,"group creation does not fetch direct conversation choices")
        vm.searchText="regina1234567"
        check(!vm.looksLikePhoneInput,"username containing digits remains a username search")
        vm.searchText="(555) 123-4567"
        check(vm.looksLikePhoneInput,"formatted phone chooses phone mode")
        print("\(count) native routing checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='chatforia-routing-qa-') as directory:
    temp=Path(directory)
    for name in ['ConversationDTO.swift','ContactDTO.swift','ChatRoomService.swift','StartChatViewModel.swift','ContactsViewModel.swift']:
        text=(src/name).read_text().replace('import Combine\n','').replace('@Published ','')
        (temp/name).write_text(text)
    (temp/'Stubs.swift').write_text(STUBS)
    (temp/'Harness.swift').write_text(HARNESS)
    executable=temp/'verify'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',*[str(p) for p in sorted(temp.glob('*.swift'))],'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True)
