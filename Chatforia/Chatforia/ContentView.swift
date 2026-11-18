import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var inviteFlow: InviteFlowManager
    @EnvironmentObject private var chatsVM: ChatsViewModel
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                SplashView()

            case .unavailable:
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: appText("randomChat.connectionProblem", languageCode: appLanguage),
                    subtitle: appText("ios.couldn_t_load_chats", languageCode: appLanguage),
                    buttonTitle: appText("common.tryAgain", languageCode: appLanguage),
                    buttonAction: { Task { await auth.retryOfflineBootstrap() } }
                )

            case .loggedOut:
                LoginView()

            case .loggedIn(let user):
                if !auth.isAppReady {
                    // Authentication, subscription and encryption setup
                    // are still being completed.
                    SplashView()

                } else if auth.needsOnboarding {
                    OnboardingView(user: user)

                } else if auth.needsKeyRestore {
                    NavigationStack {
                        RestoreEncryptionKeyView()
                    }

                } else if !chatsVM.isSessionPrepared(
                    for: auth.currentToken
                ) {
                    // Prepare the account boundary before showing the shell.
                    // The network fetch itself must not hold the splash.
                    SplashView()

                } else {
                    AppShellView(user: user)
                        .id(user.id)
                }
            }
        }
        .task(id: contentStateKey) {
            guard !auth.needsKeyRestore,
                  !auth.isOfflineSession,
                  !auth.isUnavailable else { return }

            await inviteFlow.redeemPendingInviteIfNeeded(
                auth: auth
            )
        }
        .task(id: startupLoadKey) {
            guard case .loggedIn = auth.state,
                  auth.isAppReady,
                  !auth.needsOnboarding,
                  !auth.needsKeyRestore else {
                return
            }

            guard let token = auth.currentToken,
                  !token.isEmpty else {
                auth.handleInvalidSession()
                return
            }

            chatsVM.prepareForSession(token: token)
            guard !auth.isOfflineSession else { return }

            await chatsVM.loadInitialConversationsIfNeeded(
                token: token
            )
        }
    }

    private var contentStateKey: String {
        switch auth.state {
        case .loading:
            return "loading"

        case .unavailable:
            return "unavailable"

        case .loggedOut:
            return "loggedOut"

        case .loggedIn(let user):
            return """
            loggedIn-\(user.id)-\
            \(auth.needsOnboarding)-\
            \(auth.needsKeyRestore)-\
            \(auth.isOfflineSession)
            """
        }
    }

    private var startupLoadKey: String {
        "\(contentStateKey)-appReady-\(auth.isAppReady)"
    }
}
