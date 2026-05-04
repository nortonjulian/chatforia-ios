import Foundation

final class RegistrationService {
    func register(
        username: String,
        email: String,
        password: String,
        phone: String? = nil,
        smsConsent: Bool? = nil
    ) async throws -> RegistrationResponseDTO {
        let cleanedPhone: String? = {
            let trimmed = phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()

        let request = RegistrationRequestDTO(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            phone: cleanedPhone,
            smsConsent: cleanedPhone == nil ? nil : smsConsent
        )

        let body = try JSONEncoder().encode(request)

        let response: RegistrationResponseDTO = try await APIClient.shared.send(
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
}
