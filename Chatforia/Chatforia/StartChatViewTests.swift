import XCTest
@testable import Chatforia

final class StartChatViewTests: XCTestCase {

    func testMakeSMSConversationBuildsCorrectDTO() {

        let view = StartChatView { _ in }

        let result = view.test_makeSMSConversation(
            phone: "+15551234567"
        )

        XCTAssertEqual(result.kind, "sms")
        XCTAssertEqual(result.title, "+15551234567")
        XCTAssertEqual(result.displayName, "+15551234567")
        XCTAssertEqual(result.phone, "+15551234567")
        XCTAssertEqual(result.isGroup, false)
        XCTAssertEqual(result.unreadCount, 0)
    }
}
