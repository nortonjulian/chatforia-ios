import Foundation

struct RiaService {
    private func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func suggestReplies(
        token: String,
        messages: [RiaContextMessageDTO],
        draft: String,
        filterProfanity: Bool
    ) async throws -> [String] {
        let body = try JSONEncoder().encode(
            SuggestRepliesRequest(
                messages: messages,
                draft: draft,
                filterProfanity: filterProfanity
            )
        )

        let response: SuggestRepliesResponse = try await withTimeout(seconds: 2.5) {
            try await APIClient.shared.send(
                APIRequest(
                    path: "ai/suggest-replies",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )
        }

        return response.suggestions
    }

    func rewriteText(
        token: String,
        text: String,
        tone: String,
        filterProfanity: Bool
    ) async throws -> [String] {
        let body = try JSONEncoder().encode(
            RewriteTextRequest(
                text: text,
                tone: tone,
                filterProfanity: filterProfanity
            )
        )

        let response: RewriteTextResponse = try await withTimeout(seconds: 6.0) {
            try await APIClient.shared.send(
                APIRequest(
                    path: "ai/rewrite",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )
        }

        return response.rewrites
    }

    func chat(
        token: String,
        messages: [RiaContextMessageDTO],
        memoryEnabled: Bool,
        filterProfanity: Bool = false
    ) async throws -> String {
        let body = try JSONEncoder().encode(
            ChatRequest(
                messages: messages,
                memoryEnabled: memoryEnabled,
                filterProfanity: filterProfanity
            )
        )

        let response: ChatResponse = try await withTimeout(seconds: 3.0) {
            try await APIClient.shared.send(
                APIRequest(
                    path: "ai/chat",
                    method: .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )
        }

        return response.reply
    }
}
