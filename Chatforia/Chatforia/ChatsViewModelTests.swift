import XCTest
@testable import Chatforia

@MainActor
final class ChatsViewModelTests: XCTestCase {

    func testRandomResumeIgnoresLateNoneAfterNewMatch() {
        var gate = RandomResumeRequestGate()
        let old = gate.begin()
        gate.invalidate() // A newer match arrived while the request was in flight.
        XCTAssertFalse(gate.acceptNone(old))
        let current = gate.begin()
        XCTAssertFalse(gate.acceptNone(old))
        XCTAssertTrue(gate.acceptNone(current))
    }

    func testRandomResumeIgnoresOutOfOrderResponses() {
        var gate = RandomResumeRequestGate()
        let old = gate.begin()
        let current = gate.begin()
        XCTAssertFalse(gate.acceptResumed(old))
        XCTAssertFalse(gate.acceptResumed(nil))
        XCTAssertTrue(gate.acceptResumed(current))
        XCTAssertFalse(gate.acceptNone(current))
    }

    func testRandomSessionRestorationKeepsAliasesAndFriendRequestState() {
        let session = RandomSession(socketPayload: [
            "roomId": 42,
            "chatRoomId": 42,
            "myAlias": "Quiet Signal 1000",
            "partnerAlias": "Bright Wave 2000",
            "iRequestedFriend": true
        ])
        XCTAssertEqual(session?.roomId, 42)
        XCTAssertEqual(session?.myAlias, "Quiet Signal 1000")
        XCTAssertEqual(session?.partnerAlias, "Bright Wave 2000")
        XCTAssertEqual(session?.iRequestedFriend, true)
        XCTAssertNil(RandomSession(socketPayload: ["roomId": 0]))
        XCTAssertNil(RandomSession(socketPayload: ["roomId": "42"]))
    }

    func testRandomMatchNavigatesOnlyAfterSheetDismissalAndRoomLoad() {
        var gate = RandomMatchNavigationGate()
        gate.begin()
        gate.matched(roomId: 42)
        XCTAssertFalse(gate.roomReady(roomId: 42))
        XCTAssertTrue(gate.didDismiss())
        XCTAssertFalse(gate.didDismiss())

        gate.begin()
        gate.matched(roomId: 43)
        XCTAssertFalse(gate.didDismiss())
        XCTAssertFalse(gate.roomReady(roomId: 42))
        XCTAssertTrue(gate.roomReady(roomId: 43))
        XCTAssertFalse(gate.roomReady(roomId: 43))
    }

    func testRandomMatchCancelledOrStaleRoomCannotNavigate() {
        var gate = RandomMatchNavigationGate()
        gate.begin()
        gate.matched(roomId: 42)
        let staleGeneration = gate.generation
        gate.cancel()
        XCTAssertNotEqual(gate.generation, staleGeneration)
        XCTAssertFalse(gate.roomReady(roomId: 42))
        XCTAssertFalse(gate.didDismiss())

        gate.begin()
        gate.matched(roomId: 44)
        XCTAssertFalse(gate.roomReady(roomId: 42))
        XCTAssertFalse(gate.didDismiss())
        XCTAssertTrue(gate.roomReady(roomId: 44))
    }

    func testRestrictedMediaPreviewDecodesWithoutThumbnail() throws {
        let json = """
        {"kind":"chat","id":9,"title":"Teen room","last":{
          "text":"","messageId":42,"hasMedia":true,"mediaCount":2,
          "mediaKinds":["IMAGE"],"thumbUrl":"old-thumbnail","mediaRestricted":true}}
        """
        let conversation = try JSONDecoder().decode(ConversationDTO.self, from: Data(json.utf8))
        XCTAssertEqual(conversation.last?.mediaRestricted, true)
        XCTAssertEqual(conversation.last?.hasMedia, false)
        XCTAssertEqual(conversation.last?.mediaCount, 0)
        XCTAssertEqual(conversation.last?.mediaKinds, [])
        XCTAssertNil(conversation.last?.thumbUrl)
    }

    func testOlderPreviewPayloadWithoutDirectionOrRestrictionStillDecodes() throws {
        let json = #"{"kind":"sms","id":8,"title":"Older thread","last":{"text":"Hi","messageId":5}}"#
        let conversation = try JSONDecoder().decode(ConversationDTO.self, from: Data(json.utf8))
        XCTAssertEqual(conversation.last?.text, "Hi")
        XCTAssertNil(conversation.last?.direction)
        XCTAssertNil(conversation.last?.mediaRestricted)
    }

    func testTeenMmsPreviewKeepsOnlyPermittedAudioAndDirection() throws {
        let mixed = #"{"kind":"sms","id":9,"title":"Teen MMS","last":{"text":"Voice note","messageId":42,"direction":"in","hasMedia":true,"mediaCount":1,"mediaKinds":["audio"],"thumbUrl":"old-thumbnail","mediaRestricted":true}}"#
        let decoded = try JSONDecoder().decode(ConversationDTO.self, from: Data(mixed.utf8))
        XCTAssertEqual(decoded.last?.direction, "in")
        XCTAssertEqual(decoded.last?.hasMedia, true)
        XCTAssertEqual(decoded.last?.mediaCount, 1)
        XCTAssertEqual(decoded.last?.mediaKinds, ["AUDIO"])
        XCTAssertNil(decoded.last?.thumbUrl)
        XCTAssertEqual(ChatsRootView().conversationSubtitle(decoded, languageCode: "en"), "Voice note")

        let imageOnly = #"{"kind":"sms","id":10,"title":"Teen MMS","last":{"text":"","messageId":43,"hasMedia":false,"mediaCount":0,"mediaKinds":[],"mediaRestricted":true}}"#
        let hidden = try JSONDecoder().decode(ConversationDTO.self, from: Data(imageOnly.utf8))
        XCTAssertEqual(hidden.last?.hasMedia, false)
        XCTAssertTrue(ChatsRootView().conversationSubtitle(hidden, languageCode: "en").contains("Images and videos"))

        let audioOnly = #"{"kind":"sms","id":11,"title":"Voice","last":{"text":"","messageId":44,"direction":"out","hasMedia":true,"mediaCount":1,"mediaKinds":["audio"]}}"#
        let voice = try JSONDecoder().decode(ConversationDTO.self, from: Data(audioOnly.utf8))
        XCTAssertEqual(voice.last?.direction, "out")
        XCTAssertEqual(voice.last?.hasMedia, true)
        XCTAssertTrue(ChatsRootView().conversationSubtitle(voice, languageCode: "en").contains("🎤"))
    }

    func testRestrictedPreviewNeverPreservesVisualKindsOrCountsFromOlderPayloads() throws {
        let legacy = #"{"text":"","messageId":42,"hasMedia":true,"mediaCount":2,"mediaKinds":["IMAGE","AUDIO"],"thumbUrl":"old-thumbnail","mediaRestricted":true}"#
        let decoded = try JSONDecoder().decode(ConversationLastDTO.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.hasMedia, true)
        XCTAssertNil(decoded.mediaCount)
        XCTAssertEqual(decoded.mediaKinds, ["AUDIO"])
        XCTAssertNil(decoded.thumbUrl)
    }

    func testRestrictedPreviewCopyRetainsDirectionButClearsMediaMetadata() throws {
        let copied = ConversationLastDTO(
            text: "Restricted media", messageId: 42, at: nil,
            hasMedia: true, mediaCount: 2, mediaKinds: ["IMAGE"],
            thumbUrl: "old-thumbnail", senderName: nil,
            direction: "out", mediaRestricted: true
        )
        let decoded = try JSONDecoder().decode(
            ConversationLastDTO.self, from: JSONEncoder().encode(copied)
        )
        XCTAssertEqual(decoded.direction, "out")
        XCTAssertEqual(decoded.mediaRestricted, true)
        XCTAssertEqual(decoded.hasMedia, false)
        XCTAssertEqual(decoded.mediaCount, 0)
        XCTAssertEqual(decoded.mediaKinds, [])
        XCTAssertNil(decoded.thumbUrl)
    }

    func testSessionPreparationClearsOtherAccountsBeforeOfflineShellAppears() {
        let vm = ChatsViewModel()
        vm.prepareForSession(token: "account-one")
        vm.conversations = [makeConversation(id: 1, title: "Private chat", kind: "chat")]
        vm.searchText = "Private"

        vm.prepareForSession(token: "account-two")

        XCTAssertTrue(vm.isSessionPrepared(for: "account-two"))
        XCTAssertFalse(vm.isSessionPrepared(for: "account-one"))
        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertFalse(vm.hasCompletedInitialLoad)
    }

    func testSameSessionPreparationKeepsExistingInMemoryChats() {
        let vm = ChatsViewModel()
        vm.prepareForSession(token: "same-account")
        vm.conversations = [makeConversation(id: 1, title: "Existing chat", kind: "chat")]

        vm.prepareForSession(token: "same-account")

        XCTAssertEqual(vm.conversations.first?.title, "Existing chat")
    }

    func testSMSReadDoesNotOptimisticallyEraseNewUnreadMessages() {
        let key = "chatforia.currentUserId"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set(7, forKey: key)

        let vm = ChatsViewModel()
        vm.conversations = [
            makeConversation(id: 67, title: "Saved alias", kind: "sms", unreadCount: 2),
            makeConversation(id: 67, title: "Chat", kind: "chat", unreadCount: 3),
            makeConversation(id: 68, title: "Other SMS", kind: "sms", unreadCount: 4)
        ]

        vm.applySMSRead(threadId: 67, accountId: 7)
        XCTAssertEqual(vm.conversations.map(\.unreadCount), [2, 3, 4])
        vm.applySMSRead(threadId: 68, accountId: 8)
        XCTAssertEqual(vm.conversations.map(\.unreadCount), [2, 3, 4])
    }

    func testFilteredConversationsReturnsAllWhenSearchEmpty() {
        let vm = ChatsViewModel()

        vm.conversations = [
            makeConversation(
                id: 1,
                title: "Julian",
                kind: "chat"
            ),
            makeConversation(
                id: 2,
                title: "Alex",
                kind: "chat"
            )
        ]

        vm.searchText = ""

        XCTAssertEqual(vm.filteredConversations.count, 2)
    }

    func testFilteredConversationsMatchesTitle() {
        let vm = ChatsViewModel()

        vm.conversations = [
            makeConversation(
                id: 1,
                title: "Julian Norton",
                kind: "chat"
            ),
            makeConversation(
                id: 2,
                title: "Alex Smith",
                kind: "chat"
            )
        ]

        vm.searchText = "julian"

        XCTAssertEqual(vm.filteredConversations.count, 1)
        XCTAssertEqual(vm.filteredConversations.first?.title, "Julian Norton")
    }

    func testFilteredConversationsMatchesPhone() {
        let vm = ChatsViewModel()

        vm.conversations = [
            makeConversation(
                id: 1,
                title: "SMS",
                kind: "sms",
                phone: "5551234567"
            )
        ]

        vm.searchText = "555"

        XCTAssertEqual(vm.filteredConversations.count, 1)
    }

    func testFilteredConversationsMatchesLastMessageText() {
        let vm = ChatsViewModel()

        vm.conversations = [
            makeConversation(
                id: 1,
                title: "Chat",
                kind: "chat",
                lastText: "hello world"
            )
        ]

        vm.searchText = "hello"

        XCTAssertEqual(vm.filteredConversations.count, 1)
    }

    func testLoadConversationsWithoutTokenSetsError() async {
        let vm = ChatsViewModel()

        await vm.loadConversations(token: nil)

        XCTAssertNotNil(vm.errorText)
        XCTAssertTrue(vm.conversations.isEmpty)
    }

    func testArchiveConversationWithoutTokenReturnsFalse() async {
        let vm = ChatsViewModel()

        let convo = makeConversation(
            id: 1,
            title: "Test",
            kind: "chat"
        )

        let result = await vm.archiveConversation(
            convo,
            token: nil
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testDeleteConversationWithoutTokenSetsError() async {
        let vm = ChatsViewModel()

        let convo = makeConversation(
            id: 1,
            title: "Test",
            kind: "chat"
        )

        await vm.deleteConversation(
            convo,
            token: nil
        )

        XCTAssertNotNil(vm.errorText)
    }
}

//
// MARK: Helpers
//

private func makeConversation(
    id: Int?,
    title: String,
    kind: String,
    phone: String? = nil,
    lastText: String? = nil,
    unreadCount: Int = 0
) -> ConversationDTO {

    ConversationDTO(
        kind: kind,
        id: id,
        title: title,
        displayName: title,
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        isGroup: false,
        phone: phone,
        unreadCount: unreadCount,
        avatarUsers: nil,
        last: ConversationLastDTO(
            text: lastText,
            messageId: 1,
            at: ISO8601DateFormatter().string(from: Date()),
            hasMedia: false,
            mediaCount: nil,
            mediaKinds: nil,
            thumbUrl: nil,
            senderName: nil
        )
    )
}
