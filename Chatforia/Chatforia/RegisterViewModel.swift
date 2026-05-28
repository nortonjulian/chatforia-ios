import Foundation
import Combine

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var phone = ""
    @Published var smsConsent = false

    @Published var isSubmitting = false
    @Published var isOAuthLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let registrationService: RegistrationService
    private let oauthService: OAuthService
    private let appleCoordinator: AppleSignInCoordinator

    init() {
        self.registrationService = RegistrationService()
        self.oauthService = OAuthService()
        self.appleCoordinator = AppleSignInCoordinator()
    }

    func submit(auth: AuthStore, languageCode: String) async {
        errorMessage = nil
        successMessage = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            errorMessage = appText("auth.usernameRequired", languageCode: languageCode)
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = appText("auth.validEmailRequired", languageCode: languageCode)
            return
        }

        guard !password.isEmpty else {
            errorMessage = appText("auth.passwordRequired", languageCode: languageCode)
            return
        }

        guard password.count >= 6 else {
            errorMessage = appText("auth.passwordMinLength", languageCode: languageCode)
            return
        }

        guard password == confirmPassword else {
            errorMessage = appText("auth.passwordsDontMatch", languageCode: languageCode)
            return
        }

        if !trimmedPhone.isEmpty && !smsConsent {
            errorMessage = appText("auth.smsConsentRequired", languageCode: languageCode)
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
                        errorMessage = appText("auth.secureKeySetupFailed", languageCode: languageCode)
                        return
                    }
                }

                await auth.setTokenAndLoadUser(token)
                return
            }

            successMessage = appText("auth.verifyEmailAfterSignup", languageCode: languageCode)
        } catch {
            errorMessage = friendlyRegistrationError(error)
        }
    }

    func handleGoogle(auth: AuthStore) async {
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

    func handleApple(auth: AuthStore) async {
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
