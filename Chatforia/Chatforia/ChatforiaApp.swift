import SwiftUI
import UIKit
import GoogleMobileAds
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        #if DEBUG
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "e2602a58d7d6e8fa8652eadeff5e1cc8",
            "eeabc7521a642912e973c52628ff8c3c"
        ]
        #endif
        
        MobileAds.shared.start { status in
            #if DEBUG
            debugLog("✅ Google Mobile Ads SDK started:", status.adapterStatusesByClassName)
            #endif
        }
        

        NotificationCoordinator.shared.configure()

        UNUserNotificationCenter.current().getNotificationSettings { settings in

            DispatchQueue.main.async {
            
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
        debugLog("❌ APNs registration failed:", error)
    }
}

@main
struct ChatforiaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var auth = AuthStore()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var notificationCoordinator = NotificationCoordinator.shared
    @StateObject private var deviceReplacementCoordinator =
        DeviceReplacementCoordinator.shared
    @StateObject private var callManager = CallManager()
    @StateObject private var inviteFlow = InviteFlowManager.shared
    @StateObject private var checkoutReturn = CheckoutReturnCoordinator()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var chatsVM = ChatsViewModel()
    
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
            .environmentObject(checkoutReturn)
            .environmentObject(settingsVM)
            .environmentObject(chatsVM)
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

                if !auth.isPaid {
                    InterstitialAdManager.shared.preloadIfNeeded()
                }
            }
            .onOpenURL { url in
                if checkoutReturn.handleIncomingURL(url) {
                    return
                }

                inviteFlow.handleIncomingURL(url)

                Task {
                    await inviteFlow.redeemPendingInviteIfNeeded(
                        auth: auth
                    )
                }
            }
            .onContinueUserActivity(
                NSUserActivityTypeBrowsingWeb
            ) { activity in
                guard let url = activity.webpageURL else {
                    return
                }

                if checkoutReturn.handleIncomingURL(url) {
                    return
                }

                inviteFlow.handleIncomingURL(url)

                Task {
                    await inviteFlow.redeemPendingInviteIfNeeded(
                        auth: auth
                    )
                }
            }
            .onChange(of: auth.currentUser?.theme) { _, newTheme in
                guard let newTheme else { return }
                themeManager.apply(code: newTheme)
                settingsVM.theme = newTheme
            }
            .confirmationDialog(
                "Replace an existing device?",
                isPresented: Binding(
                    get: {
                        deviceReplacementCoordinator.prompt != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            deviceReplacementCoordinator.clear()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let prompt =
                    deviceReplacementCoordinator.prompt {
                    ForEach(
                        prompt.existingDevices.indices,
                        id: \.self
                    ) { index in
                        let device =
                            prompt.existingDevices[index]

                        if let deviceId = device.deviceId {
                            Button(
                                replacementDeviceLabel(
                                    for: device
                                ),
                                role: .destructive
                            ) {
                                confirmDeviceReplacement(
                                    deviceId
                                )
                            }
                        }
                    }
                }

                Button("Cancel", role: .cancel) {
                    deviceReplacementCoordinator.clear()
                }
            } message: {
                Text(
                    deviceReplacementCoordinator.prompt?.message
                    ?? "Your plan allows one active device. Choose the existing device to replace."
                )
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
                    await auth.refreshCurrentUser(force: true)

                    guard let user = auth.currentUser else { return }

                    // Reload all server-backed settings, including Smart Replies.
                    settingsVM.load(from: user)

                    appLanguage =
                        user.uiLanguage
                        ?? user.preferredLanguage
                        ?? "en"

                    if let theme = user.theme {
                        themeManager.apply(code: theme)
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

            if !auth.isPaid {
                InterstitialAdManager.shared.preloadIfNeeded()
            }
        }
    }

    private func replacementDeviceLabel(
        for device: DeviceDTO
    ) -> String {
        let trimmedName =
            device.name?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let trimmedPlatform =
            device.platform?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let resolvedName =
            (
                trimmedName?.isEmpty == false
                ? trimmedName
                : nil
            )
            ?? "Existing device"

        guard
            let trimmedPlatform,
            !trimmedPlatform.isEmpty
        else {
            return resolvedName
        }

        return "\(resolvedName) • \(trimmedPlatform)"
    }

    private func confirmDeviceReplacement(
        _ replaceDeviceId: String
    ) {
        Task {
            guard
                let token = auth.currentToken,
                !token.isEmpty
            else {
                deviceReplacementCoordinator.clear()
                return
            }

            do {
                _ = try await DeviceRegistrationService.shared
                    .ensureCurrentDeviceRegistered(
                        userId: auth.currentUser?.id ?? 0,
                        token: token,
                        replaceDeviceId: replaceDeviceId
                    )

                await notificationCoordinator
                    .retryPushRegistrationIfPossible()

                callManager.startVoIPIfNeeded(
                    auth: auth
                )
            } catch let replacementError
                as DeviceReplacementRequiredError {
                debugLog(
                    "ℹ️ Device replacement still requires confirmation:",
                    replacementError.code
                )
            } catch {
                debugLog(
                    "❌ Device replacement failed:",
                    error
                )
            }
        }
    }
}
