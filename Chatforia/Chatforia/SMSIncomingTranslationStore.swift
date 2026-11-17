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

enum SMSIncomingTranslationPresentation: Equatable {
    case original
    case pending
    case translated(String)
}

// Successful translations are private, in-memory display data. They survive
// navigation between Chats and a thread, but never replace stored SMS bodies.
@MainActor
final class SMSIncomingTranslationCache: ObservableObject {
    static let shared = SMSIncomingTranslationCache()

    private struct Key: Hashable {
        let accountId: Int
        let messageId: Int
        let language: String
    }

    private struct Value {
        let original: String
        let display: String
        let storedAt: Date
    }

    @Published private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private let maxEntries = 200
    private let lifetime: TimeInterval = 60 * 60

    func text(accountId: Int, messageId: Int, language: String,
              original: String, allowTrimmedOriginal: Bool) -> String? {
        let key = Key(accountId: accountId, messageId: messageId, language: language)
        guard let value = values[key], Date().timeIntervalSince(value.storedAt) < lifetime,
              Self.matches(value.original, original, allowTrimmed: allowTrimmedOriginal) else { return nil }
        return value.display
    }

    func put(_ response: SMSIncomingTranslationResponse, accountId: Int, language: String) {
        let key = Key(accountId: accountId, messageId: response.messageId, language: language)
        order.removeAll { $0 == key }
        order.append(key)
        values[key] = Value(original: response.originalText, display: response.displayText, storedAt: Date())
        if order.count > maxEntries {
            let oldest = order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }

    static func matches(_ actual: String, _ expected: String, allowTrimmed: Bool) -> Bool {
        actual == expected || (allowTrimmed &&
            actual.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
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
    private let cache: SMSIncomingTranslationCache
    private let allowTrimmedOriginal: Bool

    static func request(messageId: Int) -> APIRequest {
        APIRequest(path: "sms/messages/\(messageId)/translation", method: .POST, requiresAuth: true)
    }

    init(
        allowTrimmedOriginal: Bool = false,
        cache: SMSIncomingTranslationCache = .shared,
        fetch: @escaping Fetch = { id, token in
            try await APIClient.shared.send(SMSIncomingTranslationStore.request(messageId: id), token: token)
        },
        delay: @escaping Delay = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.allowTrimmedOriginal = allowTrimmedOriginal
        self.cache = cache
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
            if cache.text(accountId: nextContext.accountId, messageId: message.id,
                          language: nextContext.language, original: message.body ?? "",
                          allowTrimmedOriginal: allowTrimmedOriginal) != nil { continue }
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
        guard let current, current.autoTranslate, message.isIncoming,
              let original = message.body else { return nil }
        // A caller holding an old language/account context must not read a
        // cached value after this store has switched to a different context.
        guard context == nil || context == current else { return nil }
        if let cached = cache.text(accountId: current.accountId, messageId: message.id,
                                   language: current.language, original: original,
                                   allowTrimmedOriginal: allowTrimmedOriginal) {
            return cached
        }
        guard current == context, let entry = entries[message.id],
              SMSIncomingTranslationCache.matches(entry.original, original,
                                                  allowTrimmed: allowTrimmedOriginal) else { return nil }
        return entry.display
    }

    func presentation(for message: SMSMessageDTO,
                      context current: SMSIncomingTranslationContext?) -> SMSIncomingTranslationPresentation {
        guard let current, current.autoTranslate, message.isIncoming,
              message.id > 0, message.trimmedBody != nil else { return .original }
        if let text = translatedText(for: message, context: current) { return .translated(text) }
        return context == current && completedIds.contains(message.id) ? .original : .pending
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
                  SMSIncomingTranslationCache.matches(response.originalText, message.body ?? "",
                                                      allowTrimmed: allowTrimmedOriginal),
                  response.targetLanguage.lowercased() == expected.language else {
                completedIds.insert(message.id)
                return
            }
            if response.status == "translated",
               let translated = response.translatedText, !translated.isEmpty,
               !response.displayText.isEmpty {
                cache.put(response, accountId: expected.accountId, language: expected.language)
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
