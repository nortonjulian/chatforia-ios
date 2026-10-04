import Foundation
import Combine

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published private(set) var registrationCompleted = false

    @Published var isSubmitting = false
    @Published var isOAuthLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published private(set) var pendingMfaToken: String?

    private let registrationService: RegistrationService
    private let oauthService: OAuthService
    private let appleCoordinator: AppleSignInCoordinator

    init() {
        self.registrationService = RegistrationService()
        self.oauthService = OAuthService()
        self.appleCoordinator = AppleSignInCoordinator()
    }

    func submit(auth: AuthStore, languageCode: String) async {
        guard !registrationCompleted, !isSubmitting, !isOAuthLoading, pendingMfaToken == nil else { return }
        errorMessage = nil
        successMessage = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

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

        guard password.count >= 8 else {
            errorMessage = "Password must contain at least eight characters."
            return
        }

        guard password == confirmPassword else {
            errorMessage = appText("auth.passwordsDontMatch", languageCode: languageCode)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await registrationService.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password
            )

            registrationCompleted = true
            password = ""
            confirmPassword = ""

            if let userId = response.resolvedUser?.id {
                AnalyticsManager.shared.identify(userId)
            }
            AnalyticsManager.shared.capture("user_registered", properties: [
                "method": "email",
                "hasPhone": false,
                "plan": "FREE"
            ])

            if let privateKey = response.privateKey,
                   let resolvedUser = response.resolvedUser,
                   let publicKey = resolvedUser.publicKey,
                   !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                    do {
                        try AccountKeyManager.shared.saveAccountKeys(
                            userId: resolvedUser.id,
                            publicKeyBase64: publicKey,
                            privateKeyBase64: privateKey
                        )
                    } catch {
                        errorMessage = appText(
                            "auth.secureKeySetupFailed",
                            languageCode: languageCode
                        )
                        return
                    }
                }

            if let token = response.token, !token.isEmpty {
                await auth.setTokenAndLoadUser(token)
                return
            }

            successMessage = appText("auth.verifyEmailAfterSignup", languageCode: languageCode)
        } catch {
            errorMessage = friendlyRegistrationError(error)
        }
    }

    func handleGoogle(auth: AuthStore) async {
        guard !registrationCompleted, !isSubmitting, !isOAuthLoading, pendingMfaToken == nil else { return }
        errorMessage = nil
        successMessage = nil
        isOAuthLoading = true
        defer { isOAuthLoading = false }

        do {
            let idToken = try await oauthService.signInWithGoogle()
            let response = try await oauthService.exchangeGoogleToken(idToken)
            try await acceptOAuth(response, auth: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleApple(auth: AuthStore) async {
        guard !registrationCompleted, !isSubmitting, !isOAuthLoading, pendingMfaToken == nil else { return }
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

            try await acceptOAuth(response, auth: auth)
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

    private func acceptOAuth(_ response: OAuthResponse, auth: AuthStore) async throws {
        switch try AuthenticationResult.resolve(token: response.token,
                                                mfaRequired: response.mfaRequired, mfaToken: response.mfaToken) {
        case .challenge(let challenge):
            pendingMfaToken = challenge
        case .session(let token):
            await finishOAuth(token, auth: auth)
        }
    }

    func completeMfa(code: String, auth: AuthStore) async throws {
        guard let challenge = pendingMfaToken else { throw AuthenticationResult.invalidResponse }
        let token = try await MFARequest.complete(challenge: challenge, code: code, apiClient: APIClient.shared)
        guard pendingMfaToken == challenge else { return }
        cancelMfa()
        await finishOAuth(token, auth: auth)
    }

    func cancelMfa() { pendingMfaToken = nil }

    private func finishOAuth(_ token: String, auth: AuthStore) async {
        await auth.setTokenAndLoadUser(token)
        guard auth.currentUser != nil else {
            errorMessage = "Unable to finish signing in. Please try again."
            return
        }
    }
}
