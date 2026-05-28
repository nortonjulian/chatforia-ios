import XCTest
@testable import Chatforia

final class MessageStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MessageStore.shared.clearAll()
        waitForAsyncStoreWrite()
    }

    override func tearDown() {
        MessageStore.shared.clearAll()
        waitForAsyncStoreWrite()
        super.tearDown()
    }

    func testClearAllRemovesMessages() {
        MessageStore.shared.upsertMessage(
            makeMessage(id: 1, roomId: 10, text: "Hello")
        )

        waitForAsyncStoreWrite()

        MessageStore.shared.clearAll()
        waitForAsyncStoreWrite()

        XCTAssertTrue(MessageStore.shared.currentWindow().isEmpty)
    }

    func testUpsertMessageAddsMessage() {
        MessageStore.shared.upsertMessage(
            makeMessage(id: 1, roomId: 10, text: "Hello")
        )

        waitForAsyncStoreWrite()

        XCTAssertEqual(MessageStore.shared.currentWindow().count, 1)
        XCTAssertEqual(MessageStore.shared.currentWindow().first?.id, 1)
    }

    func testUpsertMessageWithSameServerIdDoesNotDuplicate() {
        MessageStore.shared.upsertMessage(
            makeMessage(id: 1, roomId: 10, text: "Hello")
        )

        MessageStore.shared.upsertMessage(
            makeMessage(id: 1, roomId: 10, text: "Updated")
        )

        waitForAsyncStoreWrite()

        XCTAssertEqual(MessageStore.shared.currentWindow().count, 1)
    }

    func testUpsertManyAddsMultipleMessages() {
        MessageStore.shared.upsertMany([
            makeMessage(id: 1, roomId: 10, text: "One"),
            makeMessage(id: 2, roomId: 10, text: "Two")
        ])

        waitForAsyncStoreWrite()

        XCTAssertEqual(MessageStore.shared.currentWindow().count, 2)
    }

    func testMessagesAreSortedByCreatedDate() {
        let newer = makeMessage(
            id: 2,
            roomId: 10,
            text: "Newer",
            createdAt: Date().addingTimeInterval(60)
        )

        let older = makeMessage(
            id: 1,
            roomId: 10,
            text: "Older",
            createdAt: Date().addingTimeInterval(-60)
        )

        MessageStore.shared.upsertMany([newer, older])

        waitForAsyncStoreWrite()

        let messages = MessageStore.shared.currentWindow()

        XCTAssertEqual(messages.map(\.id), [1, 2])
    }

    func testRemoveMessageDeletesMessage() {
        MessageStore.shared.upsertMessage(
            makeMessage(id: 1, roomId: 10, text: "Hello")
        )

        waitForAsyncStoreWrite()

        MessageStore.shared.removeMessage(id: 1)
        waitForAsyncStoreWrite()

        XCTAssertNil(MessageStore.shared.message(withId: 1))
    }

    func testRemoveMessagesForRoomIdOnlyRemovesThatRoom() {
        MessageStore.shared.upsertMany([
            makeMessage(id: 1, roomId: 10, text: "Room 10"),
            makeMessage(id: 2, roomId: 20, text: "Room 20")
        ])

        waitForAsyncStoreWrite()

        MessageStore.shared.removeMessages(forRoomId: 10)
        waitForAsyncStoreWrite()

        let messages = MessageStore.shared.currentWindow()

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.chatRoomId, 20)
    }

    func testSetDeliveryStateCanBeReadBack() {
        MessageStore.shared.setDeliveryState(
            clientMessageId: "abc-123",
            state: .sending
        )

        waitForAsyncStoreWrite()

        XCTAssertEqual(
            MessageStore.shared.deliveryState(for: "abc-123"),
            .sending
        )
    }

    func testServerBeforeIdForPagingReturnsLowestServerId() {
        MessageStore.shared.upsertMany([
            makeMessage(id: 10, roomId: 1, text: "Ten"),
            makeMessage(id: 5, roomId: 1, text: "Five"),
            makeMessage(id: 20, roomId: 1, text: "Twenty")
        ])

        waitForAsyncStoreWrite()

        XCTAssertEqual(MessageStore.shared.serverBeforeIdForPaging(), 5)
    }
}

// MARK: - Helpers

private func makeMessage(
    id: Int,
    roomId: Int,
    text: String,
    createdAt: Date = Date()
) -> MessageDTO {
    MessageDTO(
        id: id,
        contentCiphertext: nil,
        rawContent: text,
        translations: nil,
        translatedFrom: nil,
        translatedForMe: nil,
        encryptedKeyForMe: nil,
        imageUrl: nil,
        audioUrl: nil,
        audioDurationSec: nil,
        attachments: nil,
        isExplicit: nil,
        createdAt: createdAt,
        expiresAt: nil,
        editedAt: nil,
        deletedBySender: nil,
        deletedForAll: nil,
        deletedAt: nil,
        deletedById: nil,
        sender: SenderDTO(
            id: 1,
            username: "sender",
            publicKey: nil,
            avatarUrl: nil
        ),
        readBy: nil,
        chatRoomId: roomId,
        reactionSummary: nil,
        myReactions: nil,
        revision: nil,
        clientMessageId: nil
    )
}

private func waitForAsyncStoreWrite() {
    let expectation = XCTestExpectation(description: "Wait for async MessageStore write")

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        expectation.fulfill()
    }

    XCTWaiter().wait(for: [expectation], timeout: 1.0)
}
