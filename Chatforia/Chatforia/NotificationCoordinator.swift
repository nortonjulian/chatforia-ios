import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    @Published var pendingChatRoomId: Int?

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])

            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("❌ notification auth failed:", error)
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("✅ APNs token:", token)
        Task {
            await registerPushTokenIfPossible(token)
        }
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
        guard let authToken = TokenStore.shared.read(), !authToken.isEmpty else { return }

        do {
            try await DeviceRegistrationService.shared.registerPushToken(
                pushToken,
                token: authToken
            )
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
