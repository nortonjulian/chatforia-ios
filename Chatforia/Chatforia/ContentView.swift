import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var inviteFlow: InviteFlowManager
    @EnvironmentObject private var chatsVM: ChatsViewModel

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                SplashView()

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

                } else if !chatsVM.isInitialLoadComplete(
                    for: auth.currentToken
                ) {
                    // Keep the branded splash visible while the first
                    // conversation list is being prepared.
                    SplashView()

                } else {
                    AppShellView(user: user)
                }
            }
        }
        .task(id: contentStateKey) {
            guard !auth.needsKeyRestore else { return }

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

            await chatsVM.loadInitialConversationsIfNeeded(
                token: token
            )
        }
    }

    private var contentStateKey: String {
        switch auth.state {
        case .loading:
            return "loading"

        case .loggedOut:
            return "loggedOut"

        case .loggedIn(let user):
            return """
            loggedIn-\(user.id)-\
            \(auth.needsOnboarding)-\
            \(auth.needsKeyRestore)
            """
        }
    }

    private var startupLoadKey: String {
        "\(contentStateKey)-appReady-\(auth.isAppReady)"
    }
}