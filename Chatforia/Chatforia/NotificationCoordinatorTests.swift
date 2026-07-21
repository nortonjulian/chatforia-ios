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

    func testDeviceRegisterRequestEncodesReplacementFields()
        throws {
        let request = DeviceRegisterRequest(
            deviceId: "new-device",
            name: "Julian's iPhone",
            platform: "ios",
            publicKey: "public-key",
            keyAlgorithm: "curve25519",
            keyVersion: 1,
            replaceExistingDevice: true,
            replaceDeviceId: "old-device"
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]
        )

        XCTAssertEqual(
            object["replaceExistingDevice"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["replaceDeviceId"] as? String,
            "old-device"
        )
    }

    func testReplacementErrorParsesRequiredResponse()
        throws {
        let responseBody = """
        {
          "error": "Choose the existing device to replace.",
          "code": "DEVICE_REPLACEMENT_REQUIRED",
          "existingDevices": [
            {
              "id": "device-row-1",
              "deviceId": "old-device",
              "name": "Old iPhone",
              "platform": "ios"
            }
          ]
        }
        """

        let parsed =
            DeviceRegistrationService.replacementError(
                from: APIError.server(
                    status: 409,
                    message: responseBody
                )
            )

        let error = try XCTUnwrap(parsed)

        XCTAssertEqual(
            error.code,
            "DEVICE_REPLACEMENT_REQUIRED"
        )
        XCTAssertEqual(
            error.existingDevices.first?.deviceId,
            "old-device"
        )
        XCTAssertEqual(
            error.message,
            "Choose the existing device to replace."
        )
    }

    func testReplacementErrorParsesStaleTargetResponse()
        throws {
        let responseBody = """
        {
          "message": "The selected device is no longer active.",
          "code": "DEVICE_REPLACEMENT_TARGET_STALE",
          "existingDevices": []
        }
        """

        let parsed =
            DeviceRegistrationService.replacementError(
                from: APIError.server(
                    status: 409,
                    message: responseBody
                )
            )

        let error = try XCTUnwrap(parsed)

        XCTAssertEqual(
            error.code,
            "DEVICE_REPLACEMENT_TARGET_STALE"
        )
        XCTAssertEqual(
            error.message,
            "The selected device is no longer active."
        )
    }

    func testReplacementErrorIgnoresOtherStatusCodes() {
        let responseBody = """
        {
          "code": "DEVICE_REPLACEMENT_REQUIRED"
        }
        """

        let parsed =
            DeviceRegistrationService.replacementError(
                from: APIError.server(
                    status: 402,
                    message: responseBody
                )
            )

        XCTAssertNil(parsed)
    }

}
