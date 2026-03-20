import Foundation

struct ReportResponse: Decodable {
    let success: Bool
    let reportId: Int?
}

enum ReportServiceError: Error {
    case invalidResponse
}

final class ReportService {
    static let shared = ReportService()
    private init() {}

    func submitReport(_ payload: ReportMessageRequest, token: String) async throws -> ReportResponse {
        let body = try JSONEncoder().encode(payload)

        return try await APIClient.shared.send(
            APIRequest(
                path: "messages/report",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }
}
