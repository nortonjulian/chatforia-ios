import SwiftUI

struct AppShellView: View {
    let user: UserDTO

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var hasRequestedNotifications = false

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            TabView {
                ChatsRootView()
                    .tabItem {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                    }

                NavigationStack {
                    CallHistoryView()
                }
                .tabItem {
                    Label("Calls", systemImage: "phone.fill")
                }

                ContactsRootView()
                    .tabItem {
                        Label("Contacts", systemImage: "person.2.fill")
                    }

                ProfileRootView(user: user)
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle.fill")
                    }
            }
            .tint(themeManager.palette.tabSelected)
            
            CallOverlayHostView()
                .environmentObject(themeManager)
        }
        .fullScreenCover(isPresented: $auth.needsKeyRestore) {
            NavigationStack {
                RestoreEncryptionKeyView()
            }
        }
        .onAppear {
            print("✅ APPSHELL APPEARED for user:", user.email ?? "nil")
            print("🌍 iOS apiBaseURL =", AppEnvironment.apiBaseURL)
        }
        .task {
            guard !hasRequestedNotifications else { return }
            hasRequestedNotifications = true

            await NotificationCoordinator.shared.requestAuthorization()
        }
    }
}
