import XCTest
@testable import Chatforia

@MainActor
final class NotificationCoordinatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NotificationCoordinator.shared.pendingChatRoomId = nil
        UserDefaults.standard.removeObject(forKey: "apns_token")
        TokenStore.shared.clear()
    }

    override func tearDown() {
        NotificationCoordinator.shared.pendingChatRoomId = nil
        UserDefaults.standard.removeObject(forKey: "apns_token")
        TokenStore.shared.clear()
        super.tearDown()
    }

    func testHandleNotificationUserInfoWithIntChatRoomIdSetsPendingRoom() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "chatRoomId": 123
        ])

        XCTAssertEqual(
            NotificationCoordinator.shared.pendingChatRoomId,
            123
        )
    }

    func testHandleNotificationUserInfoWithStringChatRoomIdSetsPendingRoom() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "chatRoomId": "456"
        ])

        XCTAssertEqual(
            NotificationCoordinator.shared.pendingChatRoomId,
            456
        )
    }

    func testHandleNotificationUserInfoIgnoresInvalidStringRoomId() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "chatRoomId": "not-a-number"
        ])

        XCTAssertNil(NotificationCoordinator.shared.pendingChatRoomId)
    }

    func testHandleNotificationUserInfoIgnoresMissingRoomId() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "otherKey": "value"
        ])

        XCTAssertNil(NotificationCoordinator.shared.pendingChatRoomId)
    }

    func testHandleDeviceTokenStoresHexToken() async {
        let tokenData = Data([0x00, 0x0f, 0x10, 0xab, 0xff])

        NotificationCoordinator.shared.handleDeviceToken(tokenData)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "apns_token"),
            "000f10abff"
        )
    }

    func testRetryPushRegistrationWithoutStoredTokenDoesNotCrash() async {
        await NotificationCoordinator.shared.retryPushRegistrationIfPossible()

        XCTAssertTrue(true)
    }

    func testRetryPushRegistrationWithStoredTokenButNoAuthTokenDoesNotCrash() async {
        UserDefaults.standard.set("000f10abff", forKey: "apns_token")

        await NotificationCoordinator.shared.retryPushRegistrationIfPossible()

        XCTAssertTrue(true)
    }
}
