import Combine
import Foundation

struct SMSIncomingTranslationResponse: Decodable, Equatable {
    let messageId: Int
    let originalText: String
    let translatedText: String?
    let displayText: String
    let targetLanguage: String
    let showOriginalWithTranslation: Bool
    let status: String
    let reason: String?
}

struct SMSIncomingTranslationContext: Equatable {
    let accountId: Int
    let token: String
    let threadId: Int
    let language: String
    let autoTranslate: Bool
    let showOriginalWithTranslation: Bool

    init?(accountId: Int?, token: String?, threadId: Int?, language: String?,
          autoTranslate: Bool, showOriginalWithTranslation: Bool) {
        guard let accountId, accountId > 0,
              let token, !token.isEmpty,
              let threadId, threadId > 0 else { return nil }
        self.accountId = accountId
        self.token = token
        self.threadId = threadId
        self.language = (language ?? "en").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.autoTranslate = autoTranslate
        self.showOriginalWithTranslation = showOriginalWithTranslation
    }
}

@MainActor
final class SMSIncomingTranslationStore: ObservableObject {
    typealias Fetch = @MainActor (Int, String) async throws -> SMSIncomingTranslationResponse
    typealias Delay = @MainActor (UInt64) async throws -> Void

    private struct Entry {
        let original: String
        let display: String
    }

    @Published private var entries: [Int: Entry] = [:]
    private var context: SMSIncomingTranslationContext?
    private var visibleIds: Set<Int> = []
    private var messagesById: [Int: SMSMessageDTO] = [:]
    private var completedIds: Set<Int> = []
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var taskBodies: [Int: String] = [:]
    private var taskTokens: [Int: UUID] = [:]
    private var entryOrder: [Int] = []
    private var generation = 0
    private var identityMatches: @MainActor () -> Bool = { false }
    private let fetch: Fetch
    private let delay: Delay

    static func request(messageId: Int) -> APIRequest {
        APIRequest(path: "sms/messages/\(messageId)/translation", method: .POST, requiresAuth: true)
    }

    init(
        fetch: @escaping Fetch = { id, token in
            try await APIClient.shared.send(SMSIncomingTranslationStore.request(messageId: id), token: token)
        },
        delay: @escaping Delay = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.fetch = fetch
        self.delay = delay
    }

    func update(
        messages: [SMSMessageDTO], visibleIds: Set<Int>,
        context nextContext: SMSIncomingTranslationContext?,
        isForeground: Bool,
        identityMatches: @escaping @MainActor () -> Bool
    ) {
        guard isForeground, let nextContext, nextContext.autoTranslate,
              identityMatches() else {
            reset()
            return
        }
        if context != nextContext {
            reset()
            context = nextContext
        }
        self.identityMatches = identityMatches
        self.visibleIds = visibleIds
        let owned = messages.filter {
            $0.id > 0 && $0.isIncoming &&
            ($0.threadId == nil || $0.threadId == nextContext.threadId) &&
            $0.trimmedBody != nil
        }
        messagesById = Dictionary(uniqueKeysWithValues: owned.map { ($0.id, $0) })

        for (id, task) in tasks where !visibleIds.contains(id) ||
            messagesById[id]?.body != taskBodies[id] {
            task.cancel()
            tasks.removeValue(forKey: id)
            taskBodies.removeValue(forKey: id)
            taskTokens.removeValue(forKey: id)
        }
        for (id, entry) in entries where messagesById[id]?.body != entry.original {
            entries.removeValue(forKey: id)
            completedIds.remove(id)
            entryOrder.removeAll { $0 == id }
        }

        for message in owned where visibleIds.contains(message.id) {
            guard entries[message.id] == nil,
                  !completedIds.contains(message.id),
                  tasks[message.id] == nil else { continue }
            let version = generation
            let requestToken = UUID()
            taskBodies[message.id] = message.body
            taskTokens[message.id] = requestToken
            tasks[message.id] = Task { [weak self] in
                await self?.translate(message, context: nextContext,
                                      generation: version, requestToken: requestToken)
            }
        }
    }

    func translatedText(for message: SMSMessageDTO,
                        context current: SMSIncomingTranslationContext?) -> String? {
        guard let current, current == context, current.autoTranslate,
              message.isIncoming, let entry = entries[message.id],
              entry.original == message.body else { return nil }
        return entry.display
    }

    func reset() {
        generation += 1
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        taskBodies.removeAll()
        taskTokens.removeAll()
        entries.removeAll()
        completedIds.removeAll()
        entryOrder.removeAll()
        visibleIds.removeAll()
        messagesById.removeAll()
        context = nil
        identityMatches = { false }
    }

    private func translate(_ message: SMSMessageDTO,
                           context expected: SMSIncomingTranslationContext,
                           generation version: Int, requestToken: UUID) async {
        defer {
            if generation == version, taskTokens[message.id] == requestToken {
                tasks.removeValue(forKey: message.id)
                taskBodies.removeValue(forKey: message.id)
                taskTokens.removeValue(forKey: message.id)
            }
        }
        // The backend may return "pending" while another request holds its
        // Redis lock. Three total attempts avoid indefinite polling.
        for attempt in 0..<3 {
            guard isCurrent(message, context: expected, generation: version,
                            requestToken: requestToken) else { return }
            let response: SMSIncomingTranslationResponse
            do {
                response = try await fetch(message.id, expected.token)
            } catch {
                if isCurrent(message, context: expected, generation: version,
                             requestToken: requestToken) {
                    completedIds.insert(message.id)
                }
                return
            }
            guard isCurrent(message, context: expected, generation: version,
                            requestToken: requestToken) else { return }
            guard response.messageId == message.id,
                  response.originalText == message.body,
                  response.targetLanguage.lowercased() == expected.language else {
                completedIds.insert(message.id)
                return
            }
            if response.status == "translated",
               let translated = response.translatedText, !translated.isEmpty,
               !response.displayText.isEmpty {
                entries[message.id] = Entry(original: response.originalText, display: response.displayText)
                entryOrder.append(message.id)
                if entryOrder.count > 100 {
                    let evicted = entryOrder.removeFirst()
                    entries.removeValue(forKey: evicted)
                    completedIds.remove(evicted)
                }
                completedIds.insert(message.id)
                return
            }
            if response.status != "original" || response.reason != "pending" || attempt == 2 {
                completedIds.insert(message.id)
                return
            }
            do {
                try await delay(attempt == 0 ? 500_000_000 : 1_000_000_000)
            } catch { return }
        }
    }

    private func isCurrent(_ message: SMSMessageDTO,
                           context expected: SMSIncomingTranslationContext,
                           generation version: Int, requestToken: UUID) -> Bool {
        !Task.isCancelled && generation == version && context == expected &&
        taskTokens[message.id] == requestToken &&
        identityMatches() && visibleIds.contains(message.id) &&
        messagesById[message.id]?.body == message.body
    }
}
