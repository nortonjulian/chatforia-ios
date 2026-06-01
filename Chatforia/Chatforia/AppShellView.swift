import SwiftUI

struct AppShellView: View {
    let user: UserDTO

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var hasRequestedNotifications = false

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            TabView {
                ChatsRootView()
                    .tabItem {
                        Label(
                            appText("tab_chats", languageCode: appLanguage),
                            systemImage: "bubble.left.and.bubble.right.fill"
                        )
                    }

                NavigationStack {
                    CallHistoryView()
                }
                .tabItem {
                    Label(
                        appText("tab_calls", languageCode: appLanguage),
                        systemImage: "phone.fill"
                    )
                }

                ContactsRootView()
                    .tabItem {
                        Label(
                            appText("tab_contacts", languageCode: appLanguage),
                            systemImage: "person.2.fill"
                        )
                    }

                ProfileRootView(user: user)
                    .tabItem {
                        Label(
                            appText("tab_profile", languageCode: appLanguage),
                            systemImage: "person.crop.circle.fill"
                        )
                    }
            }
            .id(appLanguage)
            .tint(themeManager.palette.tabSelected)
            .disabled(!auth.isAppReady)
            .opacity(auth.isAppReady ? 1 : 0.65)

            CallOverlayHostView()
                .environmentObject(themeManager)

            if !auth.isAppReady {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(themeManager.palette.accent)

                    Text(appText("loading_setting_things_up", languageCode: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
                .padding(18)
                .background(themeManager.palette.cardBackground)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
            }
        }
        .fullScreenCover(isPresented: .constant(false)) {
            NavigationStack {
                RestoreEncryptionKeyView()
            }
        }
        .onAppear {
        
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
