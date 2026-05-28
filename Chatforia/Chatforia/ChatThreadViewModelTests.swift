import XCTest
@testable import Chatforia

@MainActor
final class ChatThreadViewModelTests: XCTestCase {

    func testConfigureRandomSessionCreatesSession() {
        let vm = ChatThreadViewModel()

        vm.configureRandomSession(
            roomId: 123,
            myAlias: "Me",
            partnerAlias: "Partner"
        )

        XCTAssertEqual(vm.randomSession?.roomId, 123)
        XCTAssertEqual(vm.randomSession?.myAlias, "Me")
        XCTAssertEqual(vm.randomSession?.partnerAlias, "Partner")
    }

    func testConfigureRandomSessionDoesNotReplaceSameRoomSession() {
        let vm = ChatThreadViewModel()

        vm.configureRandomSession(
            roomId: 123,
            myAlias: "Me",
            partnerAlias: "Partner"
        )

        vm.configureRandomSession(
            roomId: 123,
            myAlias: "Changed",
            partnerAlias: "Changed"
        )

        XCTAssertEqual(vm.randomSession?.myAlias, "Me")
        XCTAssertEqual(vm.randomSession?.partnerAlias, "Partner")
    }

    func testReceivedTypingAddsTrimmedUsername() {
        let vm = ChatThreadViewModel()

        vm.receivedTyping(username: "  Julian  ")

        XCTAssertEqual(vm.typingUsernames, ["Julian"])
    }

    func testReceivedTypingIgnoresEmptyUsername() {
        let vm = ChatThreadViewModel()

        vm.receivedTyping(username: "   ")

        XCTAssertTrue(vm.typingUsernames.isEmpty)
    }

    func testClearTypingUsersRemovesAllTypingUsers() {
        let vm = ChatThreadViewModel()

        vm.receivedTyping(username: "Julian")
        vm.receivedTyping(username: "Alex")

        vm.clearTypingUsers()

        XCTAssertTrue(vm.typingUsernames.isEmpty)
    }

    func testConfigureCurrentUserPersistsUserId() {
        let vm = ChatThreadViewModel()

        UserDefaults.standard.removeObject(forKey: "chatforia.currentUserId")

        vm.configureCurrentUser(
            id: 42,
            username: "julian",
            publicKey: "public-key"
        )

        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "chatforia.currentUserId"),
            42
        )
    }

    func testSendMessageReturnsFalseWhenTokenMissing() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendMessage(
            roomId: 1,
            token: nil,
            text: "Hello",
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testSendMessageReturnsFalseWhenTextIsEmpty() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendMessage(
            roomId: 1,
            token: "token",
            text: "   ",
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
    }

    func testSendImageMessageReturnsFalseWhenTokenMissing() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendImageMessage(
            roomId: 1,
            token: nil,
            imageData: Data([1, 2, 3]),
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testSendImageMessageReturnsFalseWhenImageDataIsEmpty() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendImageMessage(
            roomId: 1,
            token: "token",
            imageData: Data(),
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testDeleteMessageReturnsFalseWhenTokenMissing() async {
        let vm = ChatThreadViewModel()

        let result = await vm.deleteMessage(
            messageId: 1,
            token: nil,
            deleteForEveryone: false
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testDeleteMessageReturnsTrueForLocalOnlyMessage() async {
        let vm = ChatThreadViewModel()

        let result = await vm.deleteMessage(
            messageId: -123,
            token: "token",
            deleteForEveryone: false
        )

        XCTAssertTrue(result)
    }
}

