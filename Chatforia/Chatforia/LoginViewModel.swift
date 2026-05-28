import Foundation
import Combine

@MainActor
struct ResendEmailResponse: Decodable {
    let ok: Bool?
}

struct LoginResponse: Decodable {
    let message: String
    let token: String
    let user: UserDTO
}

struct LoginRequest: Encodable {
    let identifier: String
    let password: String
}

final class LoginViewModel: ObservableObject {
    @Published var identifier = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var hasLoggedInBefore = false
    @Published var activeOAuthProvider: String?
    @Published var showResendVerification = false
    @Published var resendEmail = ""
    @Published var resendLoading = false
    @Published var resendSuccess: String?

    private let apiClient: APIClientSending
    private let oauth: OAuthService
    private let apple: AppleSignInCoordinator

    private let loginFlagKey = "chatforiaHasLoggedIn"
    private let lastIdentifierKey = "chatforia.lastIdentifier"

    init(
        apiClient: APIClientSending = APIClient.shared,
        oauth: OAuthService? = nil,
        apple: AppleSignInCoordinator? = nil
    ) {
        self.apiClient = apiClient
        self.oauth = oauth ?? OAuthService()
        self.apple = apple ?? AppleSignInCoordinator()
    }

    func onAppear() {
        errorText = nil
        hasLoggedInBefore = UserDefaults.standard.bool(forKey: loginFlagKey)
        identifier = UserDefaults.standard.string(forKey: lastIdentifierKey) ?? ""
    }

    func login(auth: AuthStore, languageCode: String) async {
        errorText = nil
        isLoading = true
        showResendVerification = false
        resendSuccess = nil
        defer { isLoading = false }

        do {
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

            let body = try JSONEncoder().encode(
                LoginRequest(identifier: trimmedIdentifier, password: password)
            )

            let resp: LoginResponse = try await apiClient.send(
                APIRequest(
                    path: "auth/login",
                    method: .POST,
                    body: body,
                    requiresAuth: false
                ),
                token: nil
            )

            errorText = nil

            UserDefaults.standard.set(true, forKey: loginFlagKey)
            UserDefaults.standard.set(trimmedIdentifier, forKey: lastIdentifierKey)
            hasLoggedInBefore = true

            await auth.setTokenAndLoadUser(resp.token)

            errorText = nil
        } catch {
            let message = error.localizedDescription

            if message.lowercased().contains("email_not_verified") {
                errorText = appText(
                    "auth.verifyEmailBeforeLogin",
                    languageCode: languageCode
                )
                resendEmail = identifier
                showResendVerification = true
                return
            }

            errorText = message
        }
    }

    func resendVerificationEmail(languageCode: String) async {
        resendLoading = true
        resendSuccess = nil
        defer { resendLoading = false }

        do {
            let body = try JSONEncoder().encode([
                "email": resendEmail
            ])

            let _: ResendEmailResponse = try await apiClient.send(
                APIRequest(
                    path: "auth/resend-email",
                    method: .POST,
                    body: body,
                    requiresAuth: false
                ),
                token: nil
            )

            resendSuccess = appText(
                "auth.verificationEmailSent",
                languageCode: languageCode
            )
        } catch {
            errorText = appText(
                "auth.resendVerificationFailed",
                languageCode: languageCode
            )
        }
    }

    func handleGoogle(auth: AuthStore) async {
        errorText = nil
        activeOAuthProvider = "google"
        defer { activeOAuthProvider = nil }

        do {
            let idToken = try await oauth.signInWithGoogle()
            let response = try await oauth.exchangeGoogleToken(idToken)
            await auth.setTokenAndLoadUser(response.token)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func handleApple(auth: AuthStore) async {
        errorText = nil
        activeOAuthProvider = "apple"
        defer { activeOAuthProvider = nil }

        do {
            let result = try await apple.start()
            let response = try await oauth.exchangeAppleToken(
                identityToken: result.token,
                nonce: result.nonce,
                firstName: result.name?.givenName,
                lastName: result.name?.familyName
            )
            await auth.setTokenAndLoadUser(response.token)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
