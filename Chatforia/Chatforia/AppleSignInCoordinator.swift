import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import Security

@MainActor
final class AppleSignInCoordinator: NSObject {

    private var continuation: CheckedContinuation<(token: String, nonce: String, name: PersonNameComponents?), Error>?
    private var currentNonce: String?
    private weak var presentationWindow: UIWindow?

    init(presentationWindow: UIWindow? = nil) {
        self.presentationWindow = presentationWindow
        super.init()
    }

    func setPresentationWindow(_ window: UIWindow?) {
        self.presentationWindow = window
    }

    func start() async throws -> (token: String, nonce: String, name: PersonNameComponents?) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let nonce = randomNonce()
            currentNonce = nonce

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)

        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)

            guard status == errSecSuccess else {
                fatalError("Unable to generate secure random bytes. OSStatus: \(status)")
            }

            for random in randoms {
                if remaining == 0 { break }
                if Int(random) < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization auth: ASAuthorization
    ) {
        guard
            let credential = auth.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            continuation?.resume(throwing: NSError(
                domain: "AppleSignInCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read Apple ID credential."]
            ))
            continuation = nil
            currentNonce = nil
            return
        }

        continuation?.resume(returning: (token, nonce, credential.fullName))
        continuation = nil
        currentNonce = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
        currentNonce = nil
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let presentationWindow {
            return presentationWindow
        }

        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        if let keyWindow = activeScene?.windows.first(where: \.isKeyWindow) {
            return keyWindow
        }

        if let firstWindow = activeScene?.windows.first {
            return firstWindow
        }

        fatalError("No valid presentation anchor available for Apple Sign-In.")
    }
}
