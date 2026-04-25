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
                    .onAppear {
                        Task { await refreshUserTheme() }
                    }
                    .tabItem {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                    }

                NavigationStack {
                    CallHistoryView()
                }
                .onAppear {
                    Task { await refreshUserTheme() }
                }
                .tabItem {
                    Label("Calls", systemImage: "phone.fill")
                }

                ContactsRootView()
                    .onAppear {
                        Task { await refreshUserTheme() }
                    }
                    .tabItem {
                        Label("Contacts", systemImage: "person.2.fill")
                    }

                ProfileRootView(user: user)
                    .onAppear {
                        Task { await refreshUserTheme() }
                    }
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle.fill")
                    }
            }
            .tint(themeManager.palette.tabSelected)

            CallOverlayHostView()
                .environmentObject(themeManager)
        }
        .fullScreenCover(isPresented: .constant(false)) {
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

    private func refreshUserTheme() async {
        await auth.refreshCurrentUser()

        if let theme = auth.currentUser?.theme {
            themeManager.apply(code: theme)
        }
    }
}
