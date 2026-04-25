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
                        Text("Create your account")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(themeManager.palette.primaryText)
                            .multilineTextAlignment(.center)

                        Text("Sign up to start messaging on Chatforia")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            ThemedOutlineButton(title: "Google") {}
        

                            ThemedOutlineButton(title: "Apple") {}
                               
                        }

                        HStack {
                            Rectangle()
                                .fill(themeManager.palette.border)
                                .frame(height: 1)

                            Text("or")
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .padding(.horizontal, 8)

                            Rectangle()
                                .fill(themeManager.palette.border)
                                .frame(height: 1)
                        }


                        if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ThemedToggleRow(
                                title: "SMS consent",
                                subtitle: "I consent to receive SMS messages from Chatforia.",
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
                            title: isSubmitting ? "Creating account..." : "Create Account",
                            action: { Task { await submit() } },
                            isFullWidth: true,
                            isDisabled: isSubmitting
                        )
                        
                        ThemedTextField(
                            title: "Username",
                            text: $username,
                            contentType: .username
                        )

                        ThemedTextField(
                            title: "Email",
                            text: $email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress
                        )

                        ThemedSecureField(
                            title: "Password",
                            text: $password,
                            contentType: .newPassword
                        )

                        ThemedSecureField(
                            title: "Confirm Password",
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
                            Text("Already have an account?")
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)

                            Text("Log in from the previous screen")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(themeManager.palette.accent)
                        }
                        .padding(.top, 4)

                        Text("By creating an account, you agree to our Terms of Service and Privacy Policy.")
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
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
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
            errorMessage = "Username is required."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Password is required."
            return
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        if !trimmedPhone.isEmpty && !smsConsent {
            errorMessage = "Please consent to SMS messages or remove the phone number."
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

            successMessage = "Account created. Please check your email to verify your account before logging in."
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
