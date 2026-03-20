import SwiftUI

@main
struct ChatforiaApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var themeManager = ThemeManager()
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
                .tint(themeManager.palette.accent)
                .task {
                    await auth.bootstrap()

                    if let user = auth.currentUser {
                        themeManager.apply(code: user.theme ?? "dawn")
                    }

                    AppEnvironment.configureSendQueueHandlersIfNeeded()
                    SendQueueManager.shared.replayQueuedJobs()
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                AppEnvironment.configureSendQueueHandlersIfNeeded()
                SendQueueManager.shared.replayQueuedJobs()
            }
        }
    }
}
