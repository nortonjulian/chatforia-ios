import SwiftUI
import UIKit
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationCoordinator.shared.configure()

        MobileAds.shared.start { initializationStatus in
            #if DEBUG
            print("✅ Google Mobile Ads SDK initialized: \(initializationStatus)")
            #endif
        }

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
    @StateObject private var callManager = CallManager()
    @StateObject private var inviteFlow = InviteFlowManager.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppEnvironment.configureSendQueueHandlersIfNeeded()
        SendQueueManager.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                CallOverlayHostView()
            }
            .environmentObject(auth)
            .environmentObject(themeManager)
            .environmentObject(notificationCoordinator)
            .environmentObject(callManager)
            .environmentObject(inviteFlow)
            .tint(themeManager.palette.accent)
            .task {
                await auth.bootstrap()

                if let user = auth.currentUser {
                    themeManager.apply(code: user.theme ?? "dawn")
                    await notificationCoordinator.requestAuthorization()
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            AppEnvironment.configureSendQueueHandlersIfNeeded()
            SendQueueManager.shared.replayQueuedJobs()

            if let token = auth.currentToken, !token.isEmpty {
                SocketManager.shared.connect(token: token)
            }

            if auth.currentUser != nil {
                callManager.startVoIPIfNeeded(auth: auth)
            }

            Task {
                await inviteFlow.redeemPendingInviteIfNeeded(auth: auth)
            }
            
            InterstitialAdManager.shared.preloadIfNeeded()
        }
    }
}
