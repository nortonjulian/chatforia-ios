import SwiftUI

struct AppShellView: View {
    let user: UserDTO

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

            CallOverlayHostView()
                .environmentObject(themeManager)
        }
        .onAppear {
        
        }
        .task {
            guard !hasRequestedNotifications else { return }
            hasRequestedNotifications = true

            if let theme = user.theme {
                themeManager.apply(code: theme)
            }
            
            await NotificationCoordinator.shared.requestAuthorization()
        }
    }
}
