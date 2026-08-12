import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    @Published var pendingChatRoomId: Int?
    @Published var pendingSMSThreadId: Int?

    private let apnsTokenDefaultsKey = "apns_token"
    private var isRegisteringPushToken = false
    private var lastRegisteredPushToken: String?
    private var lastRegisteredPushUserId: Int?
    private var hasRequestedAuthorizationThisLaunch = false

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        guard !hasRequestedAuthorizationThisLaunch else {
            return
        }

        hasRequestedAuthorizationThisLaunch = true

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])


            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            debugLog("❌ notification auth failed:", error)
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        debugLog("✅ APNs credentials received")

        UserDefaults.standard.set(token, forKey: apnsTokenDefaultsKey)

        Task {
            await retryPushRegistrationIfPossible()
        }
    }

    func retryPushRegistrationIfPossible() async {
        guard let pushToken = UserDefaults.standard.string(forKey: apnsTokenDefaultsKey),
              !pushToken.isEmpty else {
            return
        }

        await registerPushTokenIfPossible(pushToken)
    }

    @discardableResult
    func handleBackgroundNotification(
        _ userInfo: [AnyHashable: Any]
    ) -> Bool {
        let notificationType =
            (userInfo["type"] as? String)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        let callLifecycleTypes: Set<String> = [
            "call_ended",
            "call_answered_elsewhere",
        ]

        guard
            let notificationType,
            callLifecycleTypes.contains(
                notificationType
            )
        else {
            return false
        }

        NotificationCenter.default.post(
            name: .socketCallEnded,
            object: nil,
            userInfo: userInfo
        )

        return true
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        let notificationType =
            (userInfo["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

        if notificationType == "sms_message" {
            if let threadId = userInfo["threadId"] as? Int,
               threadId > 0 {
                pendingSMSThreadId = threadId
                return
            }

            if let threadIdNumber = userInfo["threadId"] as? NSNumber,
               threadIdNumber.intValue > 0 {
                pendingSMSThreadId = threadIdNumber.intValue
                return
            }

            if let threadIdString = userInfo["threadId"] as? String,
               let threadId = Int(threadIdString),
               threadId > 0 {
                pendingSMSThreadId = threadId
                return
            }

            return
        }

        if let roomId = userInfo["chatRoomId"] as? Int {
            pendingChatRoomId = roomId
            return
        }

        if let roomIdString = userInfo["chatRoomId"] as? String,
           let roomId = Int(roomIdString) {
            pendingChatRoomId = roomId
        }
    }

    private func registerPushTokenIfPossible(_ pushToken: String) async {
        guard !isRegisteringPushToken else {
            return
        }

        let currentUserId =
            UserDefaults.standard.integer(
                forKey: "chatforia.currentUserId"
            )

        guard currentUserId > 0 else {
            return
        }

        guard
            lastRegisteredPushToken != pushToken
                || lastRegisteredPushUserId != currentUserId
        else {
            return
        }

        guard let authToken = TokenStore.shared.read(), !authToken.isEmpty else {
            return
        }

        isRegisteringPushToken = true
        defer { isRegisteringPushToken = false }

        do {
            _ = try await DeviceRegistrationService.shared.ensureCurrentDeviceRegistered(
                userId: currentUserId,
                token: authToken
            )

            try await DeviceRegistrationService.shared.registerPushToken(
                pushToken,
                token: authToken
            )

            lastRegisteredPushToken = pushToken
            lastRegisteredPushUserId = currentUserId

        } catch {
            debugLog("❌ push token registration failed:", error)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        let notificationType =
            (userInfo["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

        let senderId: Int? = {
            if let value = userInfo["senderId"] as? Int {
                return value
            }

            if let value = userInfo["senderId"] as? NSNumber {
                return value.intValue
            }

            if let value = userInfo["senderId"] as? String {
                return Int(value)
            }

            return nil
        }()

        let currentUserId =
            UserDefaults.standard.integer(
                forKey: "chatforia.currentUserId"
            )

        let isMessageNotification =
            notificationType == "message_new"
                || notificationType == "message:new"

        if isMessageNotification,
           currentUserId > 0,
           senderId == currentUserId {
            completionHandler([])
            return
        }

        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.handleNotificationUserInfo(response.notification.request.content.userInfo)
        }
        completionHandler()
    }
}
