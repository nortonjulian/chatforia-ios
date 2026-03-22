import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationCoordinator.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCoordinator.shared.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ APNs registration failed:", error)
    }
}

@main
struct ChatforiaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var auth = AuthStore()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var notificationCoordinator = NotificationCoordinator.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppEnvironment.configureSendQueueHandlersIfNeeded()
        SendQueueManager.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(themeManager)
                .environmentObject(notificationCoordinator)
                .tint(themeManager.palette.accent)
                .task {
                    await auth.bootstrap()

                    if let user = auth.currentUser {
                        themeManager.apply(code: user.theme ?? "dawn")
                        await notificationCoordinator.requestAuthorization()
                    }

                    AppEnvironment.configureSendQueueHandlersIfNeeded()
                    SendQueueManager.shared.replayQueuedJobs()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            AppEnvironment.configureSendQueueHandlersIfNeeded()
            SendQueueManager.shared.replayQueuedJobs()

            if let token = auth.currentToken, !token.isEmpty {
                SocketManager.shared.connect(token: token)
            }
        }
    }
}
