import Foundation

@MainActor
final class RegistrationService {
    private let apiClient: APIClientSending

    init(apiClient: APIClientSending = APIClient.shared) {
        self.apiClient = apiClient
    }

    func register(
        username: String,
        email: String,
        password: String
    ) async throws -> RegistrationResponseDTO {
        let request = makeRegistrationRequest(
            username: username,
            email: email,
            password: password
        )

        let body = try JSONEncoder().encode(request)

        let response: RegistrationResponseDTO = try await apiClient.send(
            APIRequest(
                path: "auth/register",
                method: .POST,
                body: body,
                requiresAuth: false
            ),
            token: nil
        )

        return response
    }

    internal func makeRegistrationRequest(
        username: String,
        email: String,
        password: String
    ) -> RegistrationRequestDTO {
        return RegistrationRequestDTO(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }
}
