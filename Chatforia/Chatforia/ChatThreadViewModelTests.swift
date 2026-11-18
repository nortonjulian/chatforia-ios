import XCTest
@testable import Chatforia

@MainActor
final class ChatThreadViewModelTests: XCTestCase {

    func testContactAccountReportUsesAuthenticatedModerationRoute() throws {
        let path = ContactAccountReportRequest.path(userId: 29)
        let request = APIRequest(path: path, method: .POST, requiresAuth: true)
        XCTAssertEqual(try APIClient.shared.buildURL(from: request).path, "/reports/users/29")
        let payload = ContactAccountReportRequest(reason: ReportReason.harassment.rawValue, details: "synthetic")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(object["reason"] as? String, "harassment")
        XCTAssertEqual(object["details"] as? String, "synthetic")
    }

    func testReportSubmissionUsesExistingAuthenticatedRouteAndSelectedMessage() async throws {
        let request = APIRequest(
            path: ReportCreateRequest.endpoint,
            method: .POST,
            requiresAuth: true
        )
        XCTAssertEqual(try APIClient.shared.buildURL(from: request).path, "/messages/report")

        let vm = ChatThreadViewModel()
        let message = MessageDTO(
            id: 802, rawContent: "synthetic report", createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        var sent = 0
        vm.reportSender = { payload, token in
            sent += 1
            XCTAssertEqual(token, "synthetic-token")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
            XCTAssertEqual(object["messageId"] as? Int, 802)
            XCTAssertEqual(object["chatRoomId"] as? Int, 10)
            XCTAssertEqual(object["reportedUserId"] as? Int, 9)
            XCTAssertEqual(object["reason"] as? String, "sexual_content")
            let snapshots = try XCTUnwrap(object["messages"] as? [[String: Any]])
            XCTAssertEqual(snapshots.count, 1)
            XCTAssertEqual(snapshots[0]["plaintext"] as? String, "synthetic report")
            XCTAssertEqual(object["blockAfterReport"] as? Bool, true)
            return true
        }

        let succeeded = await vm.submitReport(
            targetMessage: message, roomId: 10, reason: .sexualContent,
            details: "synthetic media", reportedContent: "synthetic report", contextCount: 0,
            blockAfterReport: true, token: "synthetic-token"
        )
        XCTAssertTrue(succeeded)
        XCTAssertEqual(sent, 1)
        XCTAssertNil(vm.reportErrorText)
    }

    func testFailedReportRetainsErrorAndCanRetryWithoutDuplicateSubmission() async {
        let vm = ChatThreadViewModel()
        let message = MessageDTO(
            id: 803, rawContent: "synthetic report", createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        var attempts = 0
        vm.reportSender = { _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return true
        }
        let first = await vm.submitReport(
            targetMessage: message, roomId: 10, reason: .other,
            details: "", contextCount: 0, blockAfterReport: false, token: "synthetic-token"
        )
        XCTAssertFalse(first)
        XCTAssertNotNil(vm.reportErrorText)
        let second = await vm.submitReport(
            targetMessage: message, roomId: 10, reason: .other,
            details: "", contextCount: 0, blockAfterReport: false, token: "synthetic-token"
        )
        XCTAssertTrue(second)
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(vm.reportErrorText)
    }

    func testVisibleExpiryAndRestartAfterBackground() {
        let vm = ChatThreadViewModel()
        let expired = MessageDTO(
            id: 801, rawContent: "synthetic expired", createdAt: Date(),
            expiresAt: Date().addingTimeInterval(-60),
            sender: SenderDTO(id: 1, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        let live = MessageDTO(
            id: 802, rawContent: "synthetic live", createdAt: Date(),
            expiresAt: Date().addingTimeInterval(60),
            sender: SenderDTO(id: 1, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )

        vm.messages = [expired, live]
        vm.startExpiryLoop()
        XCTAssertEqual(vm.messages.map(\.id), [802])
        vm.stopExpiryLoop()

        vm.messages = [expired]
        vm.startExpiryLoop()
        XCTAssertTrue(vm.messages.isEmpty)
        vm.stopExpiryLoop()
    }

    func testGroupRiaConsentWireContract() throws {
        let on = try JSONDecoder().decode(
            GroupRiaRoomConsent.self,
            from: Data(#"{"me":{"allowAIBot":true},"allowForiaBot":false}"#.utf8)
        )
        XCTAssertTrue(on.me.allowAIBot)

        let off = try JSONDecoder().decode(
            GroupRiaRoomConsent.self,
            from: Data(#"{"me":{"allowAIBot":false}}"#.utf8)
        )
        XCTAssertFalse(off.me.allowAIBot)
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(GroupRiaConsentUpdate(allow: false)), encoding: .utf8),
            #"{"allow":false}"#
        )
    }


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

