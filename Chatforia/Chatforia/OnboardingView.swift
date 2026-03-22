import SwiftUI

struct OnboardingView: View {
    let user: UserDTO

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var step: Int = 0
    @State private var selectedLanguage: String = "en"
    @State private var isSaving = false
    @State private var errorText: String?

    private let totalSteps = 3

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                progressHeader

                Spacer()

                Group {
                    switch step {
                    case 0:
                        welcomeStep
                    case 1:
                        languageStep
                    default:
                        readyStep
                    }
                }
                .frame(maxWidth: 560)

                Spacer()

                footerButtons
            }
            .padding(24)
        }
        .task {
            selectedLanguage = normalizedInitialLanguage
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            Text("Welcome")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? themeManager.palette.accent : themeManager.palette.border)
                        .frame(height: 8)
                }
            }
            .frame(maxWidth: 240)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(themeManager.palette.accent)

            Text("Welcome to Chatforia")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text("Message globally, translate instantly, and start conversations fast.")
                .font(.body)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var languageStep: some View {
        VStack(spacing: 18) {
            Text("Choose your language")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text("This helps Chatforia personalize translation and messaging for you.")
                .font(.body)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            LanguageSelectionView(selectedLanguage: $selectedLanguage)
                .environmentObject(themeManager)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(themeManager.palette.accent)

            Text("You’re ready to chat")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text("You can start a new conversation, save contacts, and come back here later to update your settings.")
                .font(.body)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                ThemedOutlineButton(title: "Back") {
                    errorText = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step -= 1
                    }
                }
            }

            Spacer()

            ThemedGradientButton(
                title: buttonTitle,
                action: {
                    Task { await handlePrimaryTap() }
                },
                isDisabled: isSaving
            )
        }
        .frame(maxWidth: 560)
    }

    private var buttonTitle: String {
        if isSaving { return "Saving..." }
        switch step {
        case 0: return "Continue"
        case 1: return "Save Language"
        default: return "Start Chatting"
        }
    }

    private var normalizedInitialLanguage: String {
        let value = user.preferredLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : "en"
    }

    private func handlePrimaryTap() async {
        errorText = nil

        switch step {
        case 0:
            withAnimation(.easeInOut(duration: 0.2)) {
                step = 1
            }

        case 1:
            await saveLanguageAndContinue()

        default:
            auth.markOnboardingComplete()
        }
    }

    private func saveLanguageAndContinue() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorText = "Missing auth token."
            auth.handleInvalidSession()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let vm = SettingsViewModel()
            vm.load(from: auth.currentUser ?? user)
            vm.preferredLanguage = selectedLanguage

            let updatedUser = try await SettingsService.shared.updateSettings(
                vm.makeRequest(),
                token: token
            )

            auth.replaceCurrentUser(updatedUser)

            withAnimation(.easeInOut(duration: 0.2)) {
                step = 2
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
