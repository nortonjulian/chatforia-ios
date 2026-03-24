import Foundation

final class CallHistoryService {
    static let shared = CallHistoryService()
    private init() {}

    private struct HistoryResponse: Decodable {
        let items: [CallRecordDTO]
    }

    func fetchHistory(token: String) async throws -> [CallRecordDTO] {
        let response: HistoryResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/history",
                method: .GET,
                requiresAuth: true
            ),
            token: token
        )

        return response.items
    }
}
