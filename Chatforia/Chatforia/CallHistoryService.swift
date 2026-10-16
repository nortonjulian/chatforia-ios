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

    func deleteSelected(ids: [Int], token: String) async throws {
        struct Body: Encodable {
            let ids: [Int]
        }

        let body = try JSONEncoder().encode(
            Body(ids: ids)
        )

        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/history/delete-selected",
                method: .POST,
                body: body,
                requiresAuth: true
            ),
            token: token
        )
    }

    func clearHistory(token: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/history",
                method: .DELETE,
                requiresAuth: true
            ),
            token: token
        )
    }

    func acknowledgeMissedCalls(token: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.send(
            APIRequest(
                path: "calls/missed/acknowledge",
                method: .PATCH,
                requiresAuth: true
            ),
            token: token
        )
    }
}
