import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

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
                        Text("auth.createYourAccount")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(themeManager.palette.primaryText)
                            .multilineTextAlignment(.center)

                        Text(
                            String(localized:"auth.signupSubtitle")
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
                                ? String(localized:"auth.continueWithGoogle")
                                : String(localized:"auth.google")
                            ) {
                                Task { await handleGoogle() }
                            }
                            .disabled(isSubmitting || isOAuthLoading)

                            ThemedOutlineButton(
                                title: isOAuthLoading
                                ? String(localized:"auth.continueWithApple")
                                : String(localized:"auth.apple")
                            ) {
                                Task { await handleApple() }
                            }
                            .disabled(isSubmitting || isOAuthLoading)
                               
                        }

                        HStack {
                            Rectangle()
                                .fill(themeManager.palette.border)
                                .frame(height: 1)

                            Text(String(localized:"common.or"))
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .padding(.horizontal, 8)

                            Rectangle()
                                .fill(themeManager.palette.border)
                                .frame(height: 1)
                        }


                        if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ThemedToggleRow(
                                title: String(localized:"auth.smsConsent"),
                                subtitle:
                                String(
                                    localized:
                                    "auth.smsConsentSubtitle"
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
                             ? String(localized:"auth.creatingAccount")
                             : String(localized:"auth.createAccount"),
                            action: { Task { await submit() } },
                            isFullWidth: true,
                            isDisabled: isSubmitting
                        )
                        
                        ThemedTextField(
                            title: String(localized:"auth.username"),
                            text: $username,
                            contentType: .username
                        )

                        ThemedTextField(
                            title: String(localized:"auth.email"),
                            text: $email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress
                        )

                        ThemedSecureField(
                            title: String(localized:"auth.password"),
                            text: $password,
                            contentType: .newPassword
                        )

                        ThemedSecureField(
                            title: String(localized:"auth.phoneOptional"),
                            text: $confirmPassword,
                            contentType: .newPassword
                        )

                        ThemedTextField(
                            title: "Phone (optional)",
                            text: $phone,
                            keyboard: .phonePad,
                            contentType: .telephoneNumber
                        )

                        VStack(spacing: 6) {
                            Text("auth.alreadyHaveAnAccount")
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)

                            Text(
                                String(localized:"auth.loginPreviousScreen")
                            )
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(themeManager.palette.accent)
                        }
                        .padding(.top, 4)

                        Text(
                            String(localized:"auth.termsAgreement")
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
        .navigationTitle(String(localized: "common.register"))
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
            errorMessage = String(localized: "auth.usernameRequired")
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = String(localized: "auth.validEmailRequired")
            return
        }

        guard !password.isEmpty else {
            errorMessage = String(localized: "auth.passwordRequired")
            return
        }

        guard password.count >= 6 else {
            errorMessage = String(localized: "auth.passwordMinLength")
            return
        }

        guard password == confirmPassword else {
            errorMessage = String(localized: "auth.passwordsDontMatch")
            return
        }

        if !trimmedPhone.isEmpty && !smsConsent {
            errorMessage = String(localized: "auth.smsConsentRequired")
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
                        errorMessage = "Your account was created, but secure key setup failed on this device. Please try again."
                        return
                    }
                }

                await auth.setTokenAndLoadUser(token)
                return
            }

            successMessage =
                String(localized: "auth.verifyEmailAfterSignup")
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
