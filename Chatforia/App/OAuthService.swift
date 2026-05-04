import Foundation
import UIKit
import GoogleSignIn

struct OAuthResponse: Decodable {
    let token: String
}

@MainActor
final class OAuthService {

    func signInWithGoogle() async throws -> String {
        guard
            let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        else {
            throw NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing root VC"])
        }

        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing GIDClientID"])
        }

        let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String

        let config = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)

        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "No Google ID token"])
        }

        return idToken
    }

    func exchangeGoogleToken(_ idToken: String) async throws -> OAuthResponse {
        let body = try JSONEncoder().encode(["idToken": idToken])

        return try await APIClient.shared.send(
            APIRequest(
                path: "auth/oauth/google/ios",
                method: .POST,
                body: body,
                requiresAuth: false
            ),
            token: nil
        )
    }

    func exchangeAppleToken(
        identityToken: String,
        nonce: String,
        firstName: String?,
        lastName: String?
    ) async throws -> OAuthResponse {
        let payload: [String: Any] = [
            "identityToken": identityToken,
            "nonce": nonce,
            "firstName": firstName as Any,
            "lastName": lastName as Any
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)

        return try await APIClient.shared.send(
            APIRequest(
                path: "auth/oauth/apple/ios",
                method: .POST,
                body: data,
                requiresAuth: false
            ),
            token: nil
        )
    }
}
