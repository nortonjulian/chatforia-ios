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
            .disabled(!auth.isAppReady)
            .opacity(auth.isAppReady ? 1 : 0.65)

            CallOverlayHostView()
                .environmentObject(themeManager)

            if !auth.isAppReady {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(themeManager.palette.accent)

                    Text("Setting things up…")
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
                .padding(18)
                .background(themeManager.palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
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

            if let theme = auth.currentUser?.theme {
                themeManager.apply(code: theme)
            }

            await NotificationCoordinator.shared.requestAuthorization()
        }
    }
}
