import SwiftUI

struct OnboardingView: View {
    let user: UserDTO

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var step: Int = 0
    @State private var selectedLanguage: String = "en"
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var username: String = ""

    @AppStorage("chatforia_language")
    private var appLanguage = "en"

    private let totalSteps = 4

    private struct UsernameUpdateRequest: Encodable {
        let username: String
    }

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
                        usernameStep
                    case 2:
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

            if username.isEmpty {
                let currentUsername = user.username
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if currentUsername.lowercased().hasPrefix("user_")
                    || currentUsername.lowercased().hasPrefix("pending_") {

                    username = ""

                } else {
                    username = currentUsername
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            Text("common.welcome")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= step
                            ? themeManager.palette.accent
                            : themeManager.palette.border
                        )
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

            Text("common.welcomeToChatforia")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text(
                String(
                    localized: "onboarding.welcomeSubtitle"
                )
            )
            .font(.body)
            .foregroundStyle(themeManager.palette.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
        }
    }

    private var usernameStep: some View {
        VStack(spacing: 18) {

            Text("auth.chooseUsername")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text(
                String(
                    localized: "onboarding.usernameSubtitle"
                )
            )
            .font(.body)
            .foregroundStyle(themeManager.palette.secondaryText)
            .multilineTextAlignment(.center)

            TextField(
                String(localized: "auth.username"),
                text: $username
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding()
            .background(themeManager.palette.cardBackground)
            .overlay(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .stroke(
                    themeManager.palette.border,
                    lineWidth: 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .foregroundStyle(themeManager.palette.primaryText)
        }
    }

    private var languageStep: some View {
        VStack(spacing: 18) {

            Text("profile.chooseLanguage")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text(
                String(
                    localized: "onboarding.languageSubtitle"
                )
            )
            .font(.body)
            .foregroundStyle(themeManager.palette.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            LanguageSelectionView(
                selectedLanguage: $selectedLanguage
            )
            .environmentObject(themeManager)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(themeManager.palette.accent)

            Text(
                String(localized: "onboarding.readyTitle")
            )
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(themeManager.palette.primaryText)
            .multilineTextAlignment(.center)

            Text(
                String(
                    localized: "onboarding.readySubtitle"
                )
            )
            .font(.body)
            .foregroundStyle(themeManager.palette.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 430)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {

            if step > 0 {

                ThemedOutlineButton(
                    title: String(localized: "common.back")
                ) {
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
                    Task {
                        await handlePrimaryTap()
                    }
                },
                isDisabled: isSaving
            )
        }
        .frame(maxWidth: 560)
    }

    private var buttonTitle: String {

        if isSaving {
            return String(localized: "common.saving")
        }

        switch step {

        case 0:
            return String(localized: "common.continue")

        case 1:
            return String(localized: "onboarding.saveUsername")

        case 2:
            return String(localized: "onboarding.saveLanguage")

        default:
            return String(localized: "onboarding.startChatting")
        }
    }

    private var normalizedInitialLanguage: String {
        let value = user.preferredLanguage?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (value?.isEmpty == false)
            ? value!
            : "en"
    }

    private func handlePrimaryTap() async {
        errorText = nil

        switch step {

        case 0:
            withAnimation(.easeInOut(duration: 0.2)) {
                step = 1
            }

        case 1:
            await saveUsernameAndContinue()

        case 2:
            await saveLanguageAndContinue()

        default:
            auth.markOnboardingComplete()
        }
    }

    private func saveUsernameAndContinue() async {

        guard let token = auth.currentToken,
              !token.isEmpty else {

            errorText = String(
                localized: "ios.missing_auth_token"
            )
            return
        }

        let trimmed = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !trimmed.isEmpty else {
            errorText = String(
                localized: "onboarding.chooseUsernameError"
            )
            return
        }

        guard trimmed.count >= 3 else {
            errorText = String(
                localized: "onboarding.usernameTooShort"
            )
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let body = try JSONEncoder().encode(
                UsernameUpdateRequest(username: trimmed)
            )

            let updatedUser: UserDTO =
                try await APIClient.shared.send(
                    APIRequest(
                        path: "users/me",
                        method: .PATCH,
                        body: body,
                        requiresAuth: true
                    ),
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

    private func saveLanguageAndContinue() async {

        guard let token = auth.currentToken,
              !token.isEmpty else {

            errorText = String(
                localized: "ios.missing_auth_token"
            )

            auth.handleInvalidSession()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let vm = SettingsViewModel()

            vm.load(from: auth.currentUser ?? user)
            vm.preferredLanguage = selectedLanguage

            let updatedUser =
                try await SettingsService.shared.updateSettings(
                    vm.makeRequest(),
                    token: token
                )

            auth.replaceCurrentUser(updatedUser)

            appLanguage = selectedLanguage

            withAnimation(.easeInOut(duration: 0.2)) {
                step = 3
            }

        } catch {
            errorText = error.localizedDescription
        }
    }
}
