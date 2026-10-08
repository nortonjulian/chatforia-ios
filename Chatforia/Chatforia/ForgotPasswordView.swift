import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var email: String
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    init(initialEmail: String = "") {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text(appText("login.forgotPassword.title", languageCode: appLanguage))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(themeManager.palette.primaryText)
                    Text(appText("login.forgotPassword.helper", languageCode: appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 16) {
                        ThemedTextField(
                            title: appText("login.forgotPassword.emailLabel", languageCode: appLanguage),
                            text: $email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress
                        )
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("forgot.email")

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if sent {
                            Text(appText("login.forgotPassword.sentLabel", languageCode: appLanguage))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.palette.primaryText)
                            Text(appText("login.forgotPassword.sentHelper", languageCode: appLanguage))
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .multilineTextAlignment(.center)

                        }

                        ThemedGradientButton(
                            title: appText(
                                isSending ? "login.forgotPassword.sending" : "login.forgotPassword.sendCta",
                                languageCode: appLanguage
                            ),
                            action: { Task { await sendLink() } },
                            isFullWidth: true,
                            isDisabled: isSending
                        )
                        .accessibilityIdentifier("forgot.sendLink")

                        Button(appText("login.forgotPassword.backToLogin", languageCode: appLanguage)) {
                            dismiss()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                    }
                    .padding(20)
                    .background(themeManager.palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .padding()
            }
        }
        .navigationTitle(appText("login.forgotPassword.title", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendLink() async {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            errorMessage = appText("login.forgotPassword.emailInvalid", languageCode: appLanguage)
            sent = false
            return
        }

        isSending = true
        errorMessage = nil
        sent = false
        defer { isSending = false }
        do {
            try await PasswordResetService.requestLink(email: normalized)
            sent = true // Same response for known and unknown accounts.
        } catch {
            errorMessage = appText("login.forgotPassword.genericError", languageCode: appLanguage)
        }
    }

}
