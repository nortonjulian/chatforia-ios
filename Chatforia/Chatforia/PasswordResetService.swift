import Foundation

private struct ForgotPasswordRequest: Encodable {
    let email: String
}

enum PasswordResetService {
    static func requestLink(email: String) async throws {
        let body = try JSONEncoder().encode(ForgotPasswordRequest(email: email))
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(path: "auth/forgot-password", method: .POST, body: body, requiresAuth: false),
            token: nil
        )
    }
}
