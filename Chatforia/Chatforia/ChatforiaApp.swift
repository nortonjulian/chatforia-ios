import SwiftUI

@main
struct ChatforiaApp: App {
    @StateObject private var auth = AuthStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppEnvironment.configureSendQueueHandlersIfNeeded()
        SendQueueManager.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .task {
                    await auth.bootstrap()
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
