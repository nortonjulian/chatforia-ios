import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var inviteFlow: InviteFlowManager

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                SplashView()

            case .loggedOut:
                LoginView()

            case .loggedIn(let user):
                if auth.needsOnboarding {
                    OnboardingView(user: user)
                } else {
                    AppShellView(user: user)
                }
            }
        }
        .task(id: contentStateKey) {
            await inviteFlow.redeemPendingInviteIfNeeded(auth: auth)
        }
    }

    private var contentStateKey: String {
        switch auth.state {
        case .loading:
            return "loading"
        case .loggedOut:
            return "loggedOut"
        case .loggedIn(let user):
            return "loggedIn-\(user.id)-\(auth.needsOnboarding)"
        }
    }
}
