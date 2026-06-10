import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    @Published var pendingChatRoomId: Int?

    private let apnsTokenDefaultsKey = "apns_token"
    private var isRegisteringPushToken = false
    private var lastRegisteredPushToken: String?
    private var hasRequestedAuthorizationThisLaunch = false

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        guard !hasRequestedAuthorizationThisLaunch else {
            print("⏭️ Notification permission already requested this launch")
            return
        }

        hasRequestedAuthorizationThisLaunch = true

        do {
            print("🔔 Requesting notification permission...")
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])

            print("🔔 Notification permission granted:", granted)

            if granted {
                print("📲 Registering AFTER permission granted")
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("❌ notification auth failed:", error)
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("✅ APNs token:", token)

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

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
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
            print("⏭️ Push registration already in progress")
            return
        }

        guard lastRegisteredPushToken != pushToken else {
            print("⏭️ Push token already registered this launch")
            return
        }

        print("🚀 Attempting push registration...")

        guard let authToken = TokenStore.shared.read(), !authToken.isEmpty else {
            return
        }

        print("🔑 Auth token exists")

        isRegisteringPushToken = true
        defer { isRegisteringPushToken = false }

        do {
            _ = try await DeviceRegistrationService.shared.ensureCurrentDeviceRegistered(
                userId: 0,
                token: authToken
            )
            print("✅ device registered (or already exists)")

            try await DeviceRegistrationService.shared.registerPushToken(
                pushToken,
                token: authToken
            )

            lastRegisteredPushToken = pushToken

            print("✅ push token registered with backend")
        } catch {
            print("❌ push token registration failed:", error)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
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
