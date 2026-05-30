import XCTest
@testable import Chatforia

@MainActor
final class SMSThreadViewModelTests: XCTestCase {

    func testLoadThreadWithoutTokenSetsError() async {
        let vm = SMSThreadViewModel()

        await vm.loadThread(threadId: 1, token: nil)

        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isLoading)
    }

    func testSendTextMessageReturnsNilForBlankText() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendTextMessage(
            existingThreadId: 1,
            to: "+15551234567",
            text: "   ",
            token: "token"
        )

        XCTAssertNil(result)
        XCTAssertFalse(vm.isSending)
    }

    func testSendTextMessageWithoutTokenSetsError() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendTextMessage(
            existingThreadId: 1,
            to: "+15551234567",
            text: "Hello",
            token: nil
        )

        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isSending)
    }

    func testSendMediaMessageReturnsNilForEmptyMediaUrls() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendMediaMessage(
            existingThreadId: 1,
            to: "+15551234567",
            mediaUrls: [],
            token: "token"
        )

        XCTAssertNil(result)
        XCTAssertFalse(vm.isSending)
    }

    func testSendMediaMessageWithoutTokenSetsError() async {
        let vm = SMSThreadViewModel()

        let result = await vm.sendMediaMessage(
            existingThreadId: 1,
            to: "+15551234567",
            mediaUrls: ["https://example.com/image.jpg"],
            token: nil
        )

        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.isSending)
    }

    func testResolvedTitleUsesConversationTitleWhenNoThread() {
        let vm = SMSThreadViewModel()

        let title = vm.resolvedTitle(
            fallback: "  Mom  ",
            fallbackPhone: "+15551234567"
        )

        XCTAssertEqual(title, "Mom")
    }

    func testResolvedTitleUsesFallbackPhoneWhenTitleBlank() {
        let vm = SMSThreadViewModel()

        let title = vm.resolvedTitle(
            fallback: "   ",
            fallbackPhone: "  +15551234567  "
        )

        XCTAssertEqual(title, "+15551234567")
    }

    func testResolvedTitleDefaultsToSMSWhenNoThreadTitleOrPhone() {
        let vm = SMSThreadViewModel()

        let title = vm.resolvedTitle(
            fallback: "   ",
            fallbackPhone: nil
        )

        XCTAssertEqual(title, "SMS")
    }

    func testResolvedPhoneUsesFallbackPhoneWhenNoThread() {
        let vm = SMSThreadViewModel()

        let phone = vm.resolvedPhone(
            fallback: "  +15551234567  "
        )

        XCTAssertEqual(phone, "+15551234567")
    }

    func testResolvedPhoneReturnsNilWhenNoThreadAndFallbackBlank() {
        let vm = SMSThreadViewModel()

        let phone = vm.resolvedPhone(
            fallback: "   "
        )

        XCTAssertNil(phone)
    }
}
