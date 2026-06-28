import SwiftUI
import UIKit
import GoogleMobileAds
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        MobileAds.shared.start { status in
            #if DEBUG
            print("✅ Google Mobile Ads SDK started:", status.adapterStatusesByClassName)
            #endif
        }
        UnityAdsManager.shared.start()

        NotificationCoordinator.shared.configure()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("🔔 notification settings status:", settings.authorizationStatus.rawValue)

            DispatchQueue.main.async {
                print("📲 Registering for remote notifications...")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        Task { @MainActor in
            VoIPPushManager.shared.start()
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
    @StateObject private var settingsVM = SettingsViewModel()
    
    @AppStorage("chatforia_language")
    private var appLanguage = "en"


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
            .id(appLanguage)
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
            .environment(
                \.locale,
                Locale(identifier: appLanguage)
            )
            .task {
                await auth.bootstrap()

                if let user = auth.currentUser {
                    if let theme = user.theme {
                        themeManager.apply(code: theme)
                    }
                    settingsVM.load(from: user)
                    
                    appLanguage = user.uiLanguage ?? user.preferredLanguage ?? "en"
                    let path = Bundle.main.path(forResource: "es", ofType: "lproj")
                    let esBundle = path.flatMap { Bundle(path: $0) }
                    
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

                UnityInterstitialAdManager.shared.preloadIfNeeded()
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
                    
                    if let uiLanguage = auth.currentUser?.uiLanguage {
                        appLanguage = uiLanguage
                    }

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

            UnityInterstitialAdManager.shared.preloadIfNeeded()
        }
    }
}
