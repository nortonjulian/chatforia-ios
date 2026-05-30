import XCTest
@testable import Chatforia

@MainActor
final class RiaChatViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = RiaChatViewModel()

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.lastError)
        XCTAssertNil(vm.aiDisabledReason)
    }

    func testSendMessageWithoutTokenDoesNothing() async {
        let vm = RiaChatViewModel()

        await vm.sendMessage(
            token: nil,
            text: "Hello",
            memoryEnabled: true
        )

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.lastError)
        XCTAssertNil(vm.aiDisabledReason)
    }

    func testSendMessageWithEmptyTokenDoesNothing() async {
        let vm = RiaChatViewModel()

        await vm.sendMessage(
            token: "",
            text: "Hello",
            memoryEnabled: true
        )

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    func testSendMessageWithBlankTextDoesNothing() async {
        let vm = RiaChatViewModel()

        await vm.sendMessage(
            token: "token",
            text: "   ",
            memoryEnabled: true
        )

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    func testClearConversationRemovesMessagesAndErrors() {
        let vm = RiaChatViewModel()

        vm.messages = [
            RiaChatMessage(role: "user", content: "Hello"),
            RiaChatMessage(role: "assistant", content: "Hi")
        ]
        vm.lastError = "Something went wrong"
        vm.aiDisabledReason = "Disabled"

        vm.clearConversation()

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.lastError)
        XCTAssertNil(vm.aiDisabledReason)
    }

    func testSeedWelcomeIfNeededDoesNothingForNow() {
        let vm = RiaChatViewModel()

        vm.seedWelcomeIfNeeded()

        XCTAssertTrue(vm.messages.isEmpty)
    }
}
