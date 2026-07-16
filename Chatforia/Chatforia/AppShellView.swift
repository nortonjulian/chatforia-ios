import SwiftUI

struct AppShellView: View {
    let user: UserDTO

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var checkoutReturn: CheckoutReturnCoordinator

    @AppStorage("chatforia_language")
    private var appLanguage = "en"

    @State private var hasRequestedNotifications = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                ChatsRootView()
                    .tabItem {
                        Label(
                            appText(
                                "tab_chats",
                                languageCode: appLanguage
                            ),
                            systemImage:
                                "bubble.left.and.bubble.right.fill"
                        )
                    }
                    .tag(0)

                NavigationStack {
                    CallHistoryView()
                }
                .tabItem {
                    Label(
                        appText(
                            "tab_calls",
                            languageCode: appLanguage
                        ),
                        systemImage: "phone.fill"
                    )
                }
                .tag(1)

                ContactsRootView()
                    .tabItem {
                        Label(
                            appText(
                                "tab_contacts",
                                languageCode: appLanguage
                            ),
                            systemImage: "person.2.fill"
                        )
                    }
                    .tag(2)

                ProfileRootView(user: user)
                    .tabItem {
                        Label(
                            appText(
                                "tab_profile",
                                languageCode: appLanguage
                            ),
                            systemImage:
                                "person.crop.circle.fill"
                        )
                    }
                    .tag(3)
            }
            .id(appLanguage)
            .tint(themeManager.palette.tabSelected)

            CallOverlayHostView()
                .environmentObject(themeManager)
        }
        .onAppear {
            if checkoutReturn.pendingEvent != nil {
                selectedTab = 3
            }
        }
        .onChange(
            of: checkoutReturn.pendingEvent?.id
        ) { _, eventID in
            if eventID != nil {
                selectedTab = 3
            }
        }
        .task {
            guard !hasRequestedNotifications else {
                return
            }

            hasRequestedNotifications = true

            if let theme = user.theme {
                themeManager.apply(code: theme)
            }

            await NotificationCoordinator.shared
                .requestAuthorization()
        }
    }
}
