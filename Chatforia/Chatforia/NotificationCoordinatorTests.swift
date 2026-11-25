import XCTest
@testable import Chatforia

@MainActor
final class NotificationCoordinatorTests: XCTestCase {

    private func key(_ id: Int = 42, account: Int = 7,
                     channel: IncomingNotificationChannel = .sms) -> IncomingNotificationKey {
        IncomingNotificationKey(accountId: account, channel: channel, messageId: id)
    }

    func testSocketThenAPNsUsesNativeSoundAndOneVisualAlert() {
        var ledger = IncomingNotificationLedger()
        let first = ledger.socket(key())
        XCTAssertFalse(first.sound)
        XCTAssertTrue(first.visualAlert)
        XCTAssertTrue(first.scheduleFallbackBanner)
        let push = ledger.apns(key(), bannerEligible: true)
        XCTAssertTrue(push.sound)
        XCTAssertFalse(push.visualAlert)
        XCTAssertTrue(push.banner)
        XCTAssertFalse(ledger.fireFallbackBanner(key(), bannerEligible: true))
        XCTAssertFalse(ledger.apns(key()).sound)
        XCTAssertFalse(ledger.apns(key(), bannerEligible: true).banner)
    }

    func testAPNsThenSocketNeverSchedulesFallback() {
        var ledger = IncomingNotificationLedger()
        let push = ledger.apns(key(), bannerEligible: true)
        XCTAssertTrue(push.sound)
        XCTAssertTrue(push.visualAlert)
        XCTAssertTrue(push.banner)
        let socket = ledger.socket(key())
        XCTAssertFalse(socket.sound)
        XCTAssertFalse(socket.visualAlert)
        XCTAssertFalse(socket.scheduleFallbackBanner)
    }

    func testSocketOnlyBannerThenLateAPNsHasOneBannerAndOneNativeSound() {
        var ledger = IncomingNotificationLedger()
        XCTAssertTrue(ledger.socket(key()).scheduleFallbackBanner)
        XCTAssertTrue(ledger.fireFallbackBanner(key(), bannerEligible: true))
        let latePush = ledger.apns(key(), bannerEligible: true)
        XCTAssertFalse(latePush.banner)
        XCTAssertTrue(latePush.sound)
        XCTAssertFalse(latePush.visualAlert)
        XCTAssertFalse(ledger.apns(key(), bannerEligible: true).sound)
        XCTAssertFalse(ledger.socket(key()).scheduleFallbackBanner)
    }

    func testSocketOnlyOnChatsListOrReceivingThreadDoesNotShowFallbackBanner() {
        var ledger = IncomingNotificationLedger()
        var screen = ForegroundMessageScreen()
        screen.selectedTab = 0
        screen.chatsListVisible = true
        XCTAssertTrue(ledger.socket(key()).scheduleFallbackBanner)
        XCTAssertFalse(ledger.fireFallbackBanner(
            key(), bannerEligible: screen.showsBanner(channel: .sms, conversationId: 10)
        ))
        XCTAssertTrue(ledger.apns(key(), bannerEligible: false).sound)

        screen.chatsListVisible = false
        screen.visibleChannel = .sms
        screen.visibleConversationId = 10
        XCTAssertTrue(ledger.socket(key(43)).scheduleFallbackBanner)
        XCTAssertFalse(ledger.fireFallbackBanner(
            key(43), bannerEligible: screen.showsBanner(channel: .sms, conversationId: 10)
        ))
    }

    func testDuplicateAPNsCannotShowAnotherBannerAfterScreenChanges() {
        var ledger = IncomingNotificationLedger()
        XCTAssertFalse(ledger.apns(key(), bannerEligible: false).banner)
        XCTAssertFalse(ledger.apns(key(), bannerEligible: true).banner)
        XCTAssertTrue(ledger.apns(key(43), bannerEligible: true).banner)
    }

    func testDuplicateEventsAndSeparateMessagesChannelsAndAccounts() {
        var ledger = IncomingNotificationLedger()
        XCTAssertTrue(ledger.socket(key()).scheduleFallbackBanner)
        XCTAssertFalse(ledger.socket(key()).scheduleFallbackBanner)
        XCTAssertTrue(ledger.socket(key(43)).scheduleFallbackBanner)
        XCTAssertTrue(ledger.socket(key(channel: .chat)).scheduleFallbackBanner)
        XCTAssertTrue(ledger.socket(key(account: 8)).scheduleFallbackBanner)
        XCTAssertTrue(ledger.apns(key(43)).sound)
        XCTAssertTrue(ledger.apns(key(channel: .chat)).sound)
        XCTAssertTrue(ledger.apns(key(account: 8)).sound)
    }

    func testPersistedChatSoundGateIsAccountScoped() {
        XCTAssertNotEqual(SocketManager.soundedMessageIdsKey(for: 7),
                          SocketManager.soundedMessageIdsKey(for: 8))
    }

    func testBackgroundCancellationAndAccountResetPreventFallback() {
        var ledger = IncomingNotificationLedger()
        XCTAssertTrue(ledger.socket(key()).scheduleFallbackBanner)
        ledger.cancelFallbackBanners()
        XCTAssertFalse(ledger.fireFallbackBanner(key(), bannerEligible: true))
        ledger.reset()
        XCTAssertEqual(ledger.count, 0)
        XCTAssertFalse(ledger.fireFallbackBanner(key(), bannerEligible: true))
    }

    func testSocketDeliveryNeverClaimsAudioAndDeduplicatesVisualAlert() {
        var ledger = IncomingNotificationLedger()
        let socket = ledger.socket(key())
        XCTAssertFalse(socket.sound)
        XCTAssertTrue(socket.visualAlert)
        XCTAssertFalse(ledger.socket(key()).visualAlert)
        XCTAssertTrue(ledger.apns(key()).sound)
    }

    func testLedgerIsBoundedAndExpiresOldEntries() {
        var ledger = IncomingNotificationLedger()
        let now = Date(timeIntervalSince1970: 1_000)
        for id in 1...600 {
            _ = ledger.apns(key(id), now: now)
        }
        XCTAssertEqual(ledger.count, 512)
        _ = ledger.apns(key(999), now: now.addingTimeInterval(301))
        XCTAssertEqual(ledger.count, 1)
    }

    func testForegroundScreenPresentationByTabAndConversation() {
        var screen = ForegroundMessageScreen()
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 10))
        screen.selectedTab = 0
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 10))
        screen.chatsListVisible = true
        XCTAssertFalse(screen.showsBanner(channel: .sms, conversationId: 10))
        screen.chatsListVisible = false
        screen.visibleChannel = .sms
        screen.visibleConversationId = 10
        XCTAssertFalse(screen.showsBanner(channel: .sms, conversationId: 10))
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 11))
        XCTAssertTrue(screen.showsBanner(channel: .chat, conversationId: 10))
        screen.selectedTab = 1
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 10))
        screen.selectedTab = 2
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 10))
        screen.selectedTab = 3
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 10))
    }

    func testRiaAndOtherChatsChildrenAreNotTheChatsList() {
        XCTAssertTrue(ChatsListPresentation.isVisible(
            room: false, sms: false, ria: false, startChat: false,
            matching: false, modal: false
        ))
        XCTAssertFalse(ChatsListPresentation.isVisible(
            room: false, sms: false, ria: true, startChat: false,
            matching: false, modal: false
        ))
        XCTAssertFalse(ChatsListPresentation.isVisible(
            room: true, sms: false, ria: false, startChat: false,
            matching: false, modal: false
        ))
        XCTAssertFalse(ChatsListPresentation.isVisible(
            room: false, sms: false, ria: false, startChat: true,
            matching: false, modal: false
        ))
        var screen = ForegroundMessageScreen()
        screen.selectedTab = 0
        screen.chatsListVisible = false // Ria Chat is open.
        XCTAssertTrue(screen.showsBanner(channel: .sms, conversationId: 10))
        XCTAssertTrue(screen.showsBanner(channel: .chat, conversationId: 20))
    }

    func testNotificationMessageIDParsesNewAndLegacyPayloadsSafely() {
        XCTAssertEqual(NotificationCoordinator.positiveID("700"), 700)
        XCTAssertEqual(NotificationCoordinator.positiveID(700), 700)
        XCTAssertNil(NotificationCoordinator.positiveID(nil))
        XCTAssertNil(NotificationCoordinator.positiveID("invalid"))
        XCTAssertNil(NotificationCoordinator.positiveID(0))
        XCTAssertNil(NotificationCoordinator.positiveID(true))
    }

    func testForegroundFallbackUsesExistingLocalizedGenericMessageLabel() {
        XCTAssertEqual(appText("common.message", languageCode: "en"), "Message")
        XCTAssertNotEqual(appText("common.message", languageCode: "es"), "common.message")
    }

    override func setUp() {
        super.setUp()
        NotificationCoordinator.shared.pendingChatRoomId = nil
        NotificationCoordinator.shared.pendingSMSThreadId = nil
        UserDefaults.standard.removeObject(forKey: "apns_token")
        TokenStore.shared.clear()
    }

    override func tearDown() {
        NotificationCoordinator.shared.pendingChatRoomId = nil
        NotificationCoordinator.shared.pendingSMSThreadId = nil
        UserDefaults.standard.removeObject(forKey: "apns_token")
        TokenStore.shared.clear()
        super.tearDown()
    }

    func testRegistrationCompletionAcceptsUnchangedIdentityAndToken() {
        XCTAssertTrue(NotificationCoordinator.registrationStillCurrent(
            attemptedUserId: 1,
            attemptedPushToken: "token-A",
            currentUserId: 1,
            currentPushToken: "token-A"
        ))
    }

    func testRegistrationCompletionRejectsAccountSwitch() {
        XCTAssertFalse(NotificationCoordinator.registrationStillCurrent(
            attemptedUserId: 1,
            attemptedPushToken: "token-A",
            currentUserId: 2,
            currentPushToken: "token-A"
        ))
    }

    func testRegistrationCompletionRejectsTokenRotation() {
        XCTAssertFalse(NotificationCoordinator.registrationStillCurrent(
            attemptedUserId: 1,
            attemptedPushToken: "token-A",
            currentUserId: 1,
            currentPushToken: "token-B"
        ))
    }

    func testRegistrationCompletionRejectsMissingTokenOrSignedOutUser() {
        XCTAssertFalse(NotificationCoordinator.registrationStillCurrent(
            attemptedUserId: 1,
            attemptedPushToken: "token-A",
            currentUserId: 0,
            currentPushToken: nil
        ))
    }

    func testSMSNotificationWithStringThreadIdSetsPendingThread() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "type": "sms_message",
            "threadId": "321",
            "fromNumber": "+15551234567"
        ])

        XCTAssertEqual(
            NotificationCoordinator.shared.pendingSMSThreadId,
            321
        )
        XCTAssertNil(
            NotificationCoordinator.shared.pendingChatRoomId
        )
    }

    func testSMSNotificationWithIntThreadIdSetsPendingThread() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "type": "sms_message",
            "threadId": 654
        ])

        XCTAssertEqual(
            NotificationCoordinator.shared.pendingSMSThreadId,
            654
        )
    }

    func testSMSNotificationIgnoresInvalidThreadId() {
        NotificationCoordinator.shared.handleNotificationUserInfo([
            "type": "sms_message",
            "threadId": "invalid"
        ])

        XCTAssertNil(
            NotificationCoordinator.shared.pendingSMSThreadId
        )
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
                    message: responseBody,
                    body: Data(responseBody.utf8)
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
                    message: responseBody,
                    body: Data(responseBody.utf8)
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
