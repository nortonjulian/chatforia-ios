import Foundation

final class PSTNCallService {
    static let shared = PSTNCallService()
    private init() {}

    func startCall(to rawNumber: String, token: String?) async throws -> PSTNCallResponseDTO {
        struct Body: Encodable {
            let to: String
        }

        let body = try JSONEncoder().encode(Body(to: rawNumber))

        return try await APIClient.shared.send(
            APIRequest(
                path: "voice/call",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }
}
