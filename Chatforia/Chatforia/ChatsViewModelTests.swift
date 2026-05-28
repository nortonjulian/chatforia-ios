import XCTest
@testable import Chatforia

@MainActor
final class ChatsViewModelTests: XCTestCase {

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
    lastText: String? = nil
) -> ConversationDTO {

    ConversationDTO(
        kind: kind,
        id: id,
        title: title,
        displayName: title,
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        isGroup: false,
        phone: phone,
        unreadCount: 0,
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
