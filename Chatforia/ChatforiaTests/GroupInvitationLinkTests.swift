import XCTest
@testable import Chatforia

final class GroupInvitationLinkTests: XCTestCase {
    func testTrustedHTTPSAndCustomScheme() {
        let code = "Valid_test-Code123"
        XCTAssertEqual(
            GroupInvitationLink.extract(from: URL(string: "https://www.chatforia.com/join/\(code)")!)?.code,
            code
        )
        XCTAssertEqual(
            GroupInvitationLink.extract(from: URL(string: "https://chatforia.com/join/\(code)")!)?.code,
            code
        )
        XCTAssertEqual(
            GroupInvitationLink.extract(from: URL(string: "chatforia://join/\(code)")!)?.code,
            code
        )
    }

    func testRejectsOtherURLsAndInvalidCodes() {
        for raw in [
            "https://other.example/join/Valid_test-Code123",
            "https://www.chatforia.com/ref/Valid_test-Code123",
            "https://www.chatforia.com/join/short",
            "https://www.chatforia.com/join/Valid_test-Code123/extra",
            "chatforia://oauth/Valid_test-Code123",
            "chatforia://checkout/esim/complete"
        ] {
            XCTAssertNil(GroupInvitationLink.extract(from: URL(string: raw)!))
        }
    }
}
