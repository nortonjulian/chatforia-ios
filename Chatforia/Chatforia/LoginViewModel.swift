import Foundation
import Combine

@MainActor
struct ResendEmailResponse: Decodable {
    let ok: Bool?
}

struct LoginResponse: Decodable {
    let message: String?
    let token: String?
    let user: UserDTO?
    let mfaRequired: Bool?
    let mfaToken: String?

    init(message: String? = nil, token: String? = nil, user: UserDTO? = nil,
         mfaRequired: Bool? = nil, mfaToken: String? = nil) {
        self.message = message
        self.token = token
        self.user = user
        self.mfaRequired = mfaRequired
        self.mfaToken = mfaToken
    }
}

extension LoginResponse {
    private enum CodingKeys: String, CodingKey {
        case message, token, user, mfaRequired, mfaToken
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        token = try values.decodeIfPresent(String.self, forKey: .token)
        mfaRequired = try values.decodeIfPresent(Bool.self, forKey: .mfaRequired)
        mfaToken = try values.decodeIfPresent(String.self, forKey: .mfaToken)
        // Challenge responses have only a limited user summary, not a UserDTO.
        if mfaRequired == true {
            user = nil
        } else {
            user = try values.decodeIfPresent(UserDTO.self, forKey: .user)
        }
    }
}

struct LoginRequest: Encodable {
    let identifier: String
    let password: String
}

@MainActor
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

    @Published private(set) var pendingMfaToken: String?
    private var pendingIdentifier: String?
    private var pendingOAuth = false

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
        password = ""
        hasLoggedInBefore = UserDefaults.standard.bool(forKey: loginFlagKey)
        identifier = UserDefaults.standard.string(forKey: lastIdentifierKey) ?? ""
    }

    func identifierDidChange(_ newValue: String) {
        let trimmedValue = newValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmedValue.isEmpty {
            UserDefaults.standard.removeObject(
                forKey: lastIdentifierKey
            )
        }

        if errorText != nil {
            errorText = nil
            showResendVerification = false
            resendSuccess = nil
        }
    }

    func login(auth: AuthStore, languageCode: String) async {
        guard !isLoading, activeOAuthProvider == nil, pendingMfaToken == nil else { return }
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

            try await acceptAuthentication(
                token: resp.token, mfaRequired: resp.mfaRequired, mfaToken: resp.mfaToken,
                identifier: trimmedIdentifier, isOAuth: false, auth: auth
            )

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
        guard !isLoading, activeOAuthProvider == nil, pendingMfaToken == nil else { return }
        errorText = nil
        activeOAuthProvider = "google"
        defer { activeOAuthProvider = nil }

        do {
            let idToken = try await oauth.signInWithGoogle()
            let response = try await oauth.exchangeGoogleToken(idToken)
            try await acceptAuthentication(
                token: response.token, mfaRequired: response.mfaRequired, mfaToken: response.mfaToken,
                identifier: nil, isOAuth: true, auth: auth
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    func handleApple(auth: AuthStore) async {
        guard !isLoading, activeOAuthProvider == nil, pendingMfaToken == nil else { return }
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
            try await acceptAuthentication(
                token: response.token, mfaRequired: response.mfaRequired, mfaToken: response.mfaToken,
                identifier: nil, isOAuth: true, auth: auth
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    func acceptAuthentication(token: String?, mfaRequired: Bool?, mfaToken: String?,
                              identifier: String?, isOAuth: Bool, auth: AuthStore) async throws {
        switch try AuthenticationResult.resolve(token: token, mfaRequired: mfaRequired, mfaToken: mfaToken) {
        case .challenge(let challenge):
            pendingIdentifier = identifier
            pendingOAuth = isOAuth
            password = ""
            pendingMfaToken = challenge
        case .session(let session):
            await finishAuthentication(session, identifier: identifier, isOAuth: isOAuth, auth: auth)
        }
    }

    func completeMfa(code: String, auth: AuthStore) async throws {
        guard let challenge = pendingMfaToken else { throw AuthenticationResult.invalidResponse }
        let token = try await MFARequest.complete(challenge: challenge, code: code, apiClient: apiClient)
        // A dismissed/replaced sheet must not complete a previous sign-in.
        guard pendingMfaToken == challenge else { return }
        let identifier = pendingIdentifier
        let isOAuth = pendingOAuth
        cancelMfa()
        await finishAuthentication(token, identifier: identifier, isOAuth: isOAuth, auth: auth)
    }

    func cancelMfa() {
        pendingMfaToken = nil
        pendingIdentifier = nil
        pendingOAuth = false
        password = ""
    }

    private func finishAuthentication(_ token: String, identifier: String?, isOAuth: Bool, auth: AuthStore) async {
        await auth.setTokenAndLoadUser(token)
        guard auth.currentUser != nil else {
            errorText = "Unable to finish signing in. Please try again."
            return
        }
        UserDefaults.standard.set(true, forKey: loginFlagKey)
        if let identifier { UserDefaults.standard.set(identifier, forKey: lastIdentifierKey) }
        hasLoggedInBefore = true
        password = ""
    }
}

// Both password and provider responses must pass the same challenge/session checks.
enum AuthenticationResult {
    case challenge(String)
    case session(String)

    static var invalidResponse: NSError {
        NSError(domain: "Authentication", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Sign-in could not be completed. Please sign in again."
        ])
    }

    static func resolve(token: String?, mfaRequired: Bool?, mfaToken: String?) throws -> AuthenticationResult {
        if mfaRequired == true {
            guard let mfaToken, !mfaToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalidResponse
            }
            return .challenge(mfaToken)
        }
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              mfaToken == nil else { throw invalidResponse }
        return .session(token)
    }
}

struct MFARequest: Encodable {
    let mfaToken: String
    let code: String

    @MainActor
    static func complete(challenge: String, code: String, apiClient: APIClientSending) async throws -> String {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw NSError(domain: "Authentication", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Enter your authenticator or backup code."
            ])
        }
        let body = try JSONEncoder().encode(MFARequest(mfaToken: challenge, code: code))
        let response: LoginResponse = try await apiClient.send(
            APIRequest(path: "auth/2fa/login", method: .POST, body: body, requiresAuth: false), token: nil
        )
        guard case .session(let token) = try AuthenticationResult.resolve(
            token: response.token, mfaRequired: response.mfaRequired, mfaToken: response.mfaToken
        ) else { throw AuthenticationResult.invalidResponse }
        return token
    }
}
