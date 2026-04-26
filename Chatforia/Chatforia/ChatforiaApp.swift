import SwiftUI
import UIKit
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        print("🚀 AppDelegate didFinishLaunching CALLED")

        NotificationCoordinator.shared.configure()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("🔔 notification settings status:", settings.authorizationStatus.rawValue)

            DispatchQueue.main.async {
                print("📲 Registering for remote notifications...")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("🔥 didRegisterForRemoteNotificationsWithDeviceToken CALLED")
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
    @StateObject private var callManager = CallManager()
    @StateObject private var inviteFlow = InviteFlowManager.shared
    @StateObject private var settingsVM = SettingsViewModel()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        AnalyticsManager.shared.configure()
        AnalyticsManager.shared.capture("app_loaded")
        AppEnvironment.configureSendQueueHandlersIfNeeded()
        SendQueueManager.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                CallOverlayHostView()
            }
            .onAppear {
                    AnalyticsManager.shared.capture("app_opened")
            }
            .environmentObject(auth)
            .environmentObject(themeManager)
            .environmentObject(notificationCoordinator)
            .environmentObject(callManager)
            .environmentObject(inviteFlow)
            .environmentObject(settingsVM)
            .tint(themeManager.palette.accent)
            .task {
                await auth.bootstrap()

                if let user = auth.currentUser {
                    if let theme = user.theme {
                        themeManager.apply(code: theme)
                    }
                    settingsVM.load(from: user)
                    settingsVM.loadLocalAISettings()

                    // 🔔 Request permission + trigger APNs
                    await notificationCoordinator.requestAuthorization()

                    // 🔁 Retry sending token AFTER auth exists
                    await notificationCoordinator.retryPushRegistrationIfPossible()

                    callManager.startVoIPIfNeeded(auth: auth)
                }

                AppEnvironment.configureSendQueueHandlersIfNeeded()
                SendQueueManager.shared.replayQueuedJobs()
                await inviteFlow.redeemPendingInviteIfNeeded(auth: auth)

                InterstitialAdManager.shared.preloadIfNeeded()
            }
            .onOpenURL { url in
                inviteFlow.handleIncomingURL(url)
                Task {
                    await inviteFlow.redeemPendingInviteIfNeeded(auth: auth)
                }
            }
            .onChange(of: auth.currentUser?.theme) { _, newTheme in
                guard let newTheme else { return }
                themeManager.apply(code: newTheme)
                settingsVM.theme = newTheme
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            AppEnvironment.configureSendQueueHandlersIfNeeded()
            SendQueueManager.shared.replayQueuedJobs()

            if let token = auth.currentToken, !token.isEmpty {
                SocketManager.shared.connect(token: token)
            }

            if auth.currentUser != nil {
                Task {
                    await auth.refreshCurrentUser()

                    print("🎨 refreshed theme =", auth.currentUser?.theme ?? "nil")

                        if let theme = auth.currentUser?.theme {
                            print("🎨 applying refreshed theme =", theme)
                            themeManager.apply(code: theme)
                            settingsVM.theme = theme
                        }
                }
                callManager.startVoIPIfNeeded(auth: auth)

                // 🔁 Retry again when app becomes active
                Task {
                    await notificationCoordinator.retryPushRegistrationIfPossible()
                }
            }

            Task {
                await inviteFlow.redeemPendingInviteIfNeeded(auth: auth)
            }

            InterstitialAdManager.shared.preloadIfNeeded()
        }
    }
}
