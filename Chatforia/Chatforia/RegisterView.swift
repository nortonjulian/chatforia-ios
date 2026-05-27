import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var phone = ""
    @State private var smsConsent = false

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var isOAuthLoading = false
    
    private let oauthService = OAuthService()
    private let appleCoordinator = AppleSignInCoordinator()
    private let registrationService = RegistrationService()

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(
                            appText(
                                "auth.createYourAccount",
                                languageCode: appLanguage
                            )
                        )
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(themeManager.palette.primaryText)
                            .multilineTextAlignment(.center)

                        Text(
                            appText(
                                "auth.signupSubtitle",
                                languageCode: appLanguage
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            ThemedOutlineButton(
                                title: isOAuthLoading
                                ? appText(
                                    "auth.continueWithGoogle",
                                    languageCode: appLanguage
                                )
                                : appText(
                                    "auth.google",
                                    languageCode: appLanguage
                                )
                            ) {
                                Task { await handleGoogle() }
                            }
                            .disabled(isSubmitting || isOAuthLoading)

                            ThemedOutlineButton(
                                title: isOAuthLoading
                                ? appText(
                                    "auth.continueWithApple",
                                    languageCode: appLanguage
                                )
                                : appText(
                                    "auth.apple",
                                    languageCode: appLanguage
                                )
                            ) {
                                Task { await handleApple() }
                            }
                            .disabled(isSubmitting || isOAuthLoading)
                               
                        }

                        HStack {
                            Rectangle()
                                .fill(themeManager.palette.border)
                                .frame(height: 1)

                            Text(
                                appText(
                                    "common.or",
                                    languageCode: appLanguage
                                )
                            )
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .padding(.horizontal, 8)

                            Rectangle()
                                .fill(themeManager.palette.border)
                                .frame(height: 1)
                        }


                        if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ThemedToggleRow(
                                title: appText(
                                    "auth.smsConsent",
                                    languageCode: appLanguage
                                ),
                                subtitle:
                                    appText(
                                        "auth.smsConsentSubtitle",
                                        languageCode: appLanguage
                                    ),
                                isOn: $smsConsent
                            )
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let successMessage {
                            Text(successMessage)
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ThemedGradientButton(
                            title:
                            isSubmitting
                             ? appText(
                                "auth.creatingAccount",
                                languageCode: appLanguage
                            )
                             : appText(
                                "auth.createAccount",
                                languageCode: appLanguage
                            ),
                            action: { Task { await submit() } },
                            isFullWidth: true,
                            isDisabled: isSubmitting
                        )
                        
                        ThemedTextField(
                            title: appText(
                                "auth.username",
                                languageCode: appLanguage
                            ),
                            text: $username,
                            contentType: .username
                        )

                        ThemedTextField(
                            title: appText(
                                "auth.email",
                                languageCode: appLanguage
                            ),
                            text: $email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress
                        )

                        ThemedSecureField(
                            title: appText(
                                "auth.password",
                                languageCode: appLanguage
                            ),
                            text: $password,
                            contentType: .newPassword
                        )

                        ThemedSecureField(
                            title: appText(
                                "auth.confirmPassword",
                                languageCode: appLanguage
                            ),
                            text: $confirmPassword,
                            contentType: .newPassword
                        )

                        ThemedTextField(
                            title: appText(
                                "auth.phoneOptional",
                                languageCode: appLanguage
                            ),
                            text: $phone,
                            keyboard: .phonePad,
                            contentType: .telephoneNumber
                        )

                        VStack(spacing: 6) {
                            Text(
                                appText(
                                    "auth.alreadyHaveAnAccount",
                                    languageCode: appLanguage
                                )
                            )
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)

                            Text(
                                appText(
                                    "auth.loginPreviousScreen",
                                    languageCode: appLanguage
                                )
                            )
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(themeManager.palette.accent)
                        }
                        .padding(.top, 4)

                        Text(
                            appText(
                                "auth.termsAgreement",
                                languageCode: appLanguage
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(20)
                    .background(themeManager.palette.cardBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(themeManager.palette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
                }
                .padding()
            }
        }
        .navigationTitle(
            appText(
                "common.register",
                languageCode: appLanguage
            )
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @MainActor
    private func handleGoogle() async {
        errorMessage = nil
        successMessage = nil
        isOAuthLoading = true
        defer { isOAuthLoading = false }

        do {
            let idToken = try await oauthService.signInWithGoogle()
            let response = try await oauthService.exchangeGoogleToken(idToken)
            await auth.setTokenAndLoadUser(response.token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleApple() async {
        errorMessage = nil
        successMessage = nil
        isOAuthLoading = true
        defer { isOAuthLoading = false }

        do {
            let result = try await appleCoordinator.start()
            let response = try await oauthService.exchangeAppleToken(
                identityToken: result.token,
                nonce: result.nonce,
                firstName: result.name?.givenName,
                lastName: result.name?.familyName
            )
            await auth.setTokenAndLoadUser(response.token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func themedField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding()
            .background(themeManager.palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(themeManager.palette.primaryText)
    }

    private func themedSecureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .padding()
            .background(themeManager.palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(themeManager.palette.primaryText)
    }

    private func submit() async {
        errorMessage = nil
        successMessage = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            errorMessage = appText(
                "auth.usernameRequired",
                languageCode: appLanguage
            )
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = appText(
                "auth.validEmailRequired",
                languageCode: appLanguage
            )
            return
        }

        guard !password.isEmpty else {
            errorMessage = appText(
                "auth.passwordRequired",
                languageCode: appLanguage
            )
            return
        }

        guard password.count >= 6 else {
            errorMessage = appText(
                "auth.passwordMinLength",
                languageCode: appLanguage
            )
            return
        }

        guard password == confirmPassword else {
            errorMessage = appText(
                "auth.passwordsDontMatch",
                languageCode: appLanguage
            )
            return
        }

        if !trimmedPhone.isEmpty && !smsConsent {
            errorMessage = appText(
                "auth.smsConsentRequired",
                languageCode: appLanguage
            )
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await registrationService.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                smsConsent: trimmedPhone.isEmpty ? nil : smsConsent
            )

            if let token = response.token {
                
                AnalyticsManager.shared.capture("user_registered", properties: [
                        "method": "email", 
                        "hasPhone": !trimmedPhone.isEmpty,
                        "plan": "FREE"
                ])
                
                if let privateKey = response.privateKey,
                   let publicKey = response.resolvedUser?.publicKey,
                   !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        try AccountKeyManager.shared.saveAccountKeys(
                            publicKeyBase64: publicKey,
                            privateKeyBase64: privateKey
                        )
                    } catch {
                        errorMessage = appText(
                            "auth.secureKeySetupFailed",
                            languageCode: appLanguage
                        )
                        return
                    }
                }

                await auth.setTokenAndLoadUser(token)
                return
            }

            successMessage =
            appText(
                "auth.verifyEmailAfterSignup",
                languageCode: appLanguage
            )
        } catch {
            errorMessage = friendlyRegistrationError(error)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func friendlyRegistrationError(_ error: Error) -> String {
        let nsError = error as NSError
        if let apiMessage = nsError.userInfo["message"] as? String, !apiMessage.isEmpty {
            return apiMessage
        }
        return error.localizedDescription
    }
}
