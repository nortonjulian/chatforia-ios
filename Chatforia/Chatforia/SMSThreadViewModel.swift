import Foundation
import Combine

private struct DeleteSMSMessageResponse: Decodable {
    let ok: Bool
}

private struct ReportPSTNMessageRequest: Encodable {
    let reason: String
    let details: String?
    let contextCount: Int
    let blockAfterReport: Bool
}

private struct ReportPSTNMessageResponse: Decodable {
    let success: Bool
}

private struct BlockPSTNNumberRequest: Encodable {
    let phone: String
}

private struct BlockPSTNNumberResponse: Decodable {
    let success: Bool
}

private struct SMSReadResponse: Decodable {
    let ok: Bool
}

private struct SMSReadRequest: Encodable {
    let messageIds: [Int]
}

/// A short-lived display window, never written to disk. SMS records must not
/// share the encrypted Chatforia message store or its room identifiers.
@MainActor
final class SMSConversationSnapshotCache {
    static let shared = SMSConversationSnapshotCache()

    struct Snapshot {
        let thread: SMSThreadDTO
        let messages: [SMSMessageDTO]
    }

    private struct Key: Hashable {
        let accountId: Int
        let threadId: Int
    }

    private struct Entry {
        var snapshot: Snapshot
        var removedIds: Set<Int>
        var storedAt: Date
    }

    private var activeAccountId: Int?
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private let maxThreads = 8
    private let maxMessagesPerThread = 200
    private let lifetime: TimeInterval = 20 * 60

    func activateAccount(_ accountId: Int) {
        guard accountId > 0 else { clear(); return }
        if activeAccountId != accountId { clear() }
        activeAccountId = accountId
    }

    func clear() {
        activeAccountId = nil
        entries.removeAll()
        order.removeAll()
    }

    func remove(accountId: Int, threadId: Int) {
        let key = Key(accountId: accountId, threadId: threadId)
        entries.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    func snapshot(accountId: Int, threadId: Int, now: Date = Date()) -> Snapshot? {
        guard activeAccountId == accountId else { return nil }
        let key = Key(accountId: accountId, threadId: threadId)
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < lifetime else {
            remove(accountId: accountId, threadId: threadId)
            return nil
        }
        return entry.snapshot
    }

    func removeMessage(_ messageId: Int, accountId: Int, threadId: Int) {
        guard activeAccountId == accountId else { return }
        let key = Key(accountId: accountId, threadId: threadId)
        guard var entry = entries[key] else { return }
        entry.removedIds.insert(messageId)
        entry.snapshot = Snapshot(
            thread: entry.snapshot.thread,
            messages: entry.snapshot.messages.filter { $0.id != messageId }
        )
        entries[key] = entry
    }

    func store(thread: SMSThreadDTO, messages: [SMSMessageDTO], accountId: Int,
               now: Date = Date()) {
        guard activeAccountId == accountId, thread.id > 0,
              thread.userId == nil || thread.userId == accountId else { return }
        let key = Key(accountId: accountId, threadId: thread.id)
        let removed = entries[key]?.removedIds ?? []
        let sorted = messages.filter {
            $0.id > 0 && !removed.contains($0.id) &&
            ($0.threadId == nil || $0.threadId == thread.id)
        }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        var unique: [Int: SMSMessageDTO] = [:]
        for message in sorted { unique[message.id] = message }
        let window = unique.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }.suffix(maxMessagesPerThread)
        let metadata = SMSThreadDTO(
            id: thread.id, userId: thread.userId, createdAt: thread.createdAt,
            updatedAt: thread.updatedAt, archivedAt: thread.archivedAt,
            contactPhone: thread.contactPhone, displayName: thread.displayName,
            contactName: thread.contactName, participants: thread.participants, messages: []
        )
        entries[key] = Entry(snapshot: Snapshot(thread: metadata, messages: Array(window)),
                             removedIds: removed, storedAt: now)
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > maxThreads {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    func excludingRemoved(_ messages: [SMSMessageDTO], accountId: Int,
                          threadId: Int) -> [SMSMessageDTO] {
        let removed = entries[Key(accountId: accountId, threadId: threadId)]?.removedIds ?? []
        return messages.filter { !removed.contains($0.id) }
    }
}

@MainActor
final class SMSThreadViewModel: ObservableObject {
    private struct ReadContext: Equatable {
        let threadId: Int
        let accountId: Int
        let token: String
    }

    @Published var thread: SMSThreadDTO?
    @Published var messages: [SMSMessageDTO] = []
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorText: String?
    
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
    }

    private var observers: [NSObjectProtocol] = []
    private var refreshVersion = 0
    private var refreshingVersion: Int?
    private var arrivalsDuringRefresh: [Int: SMSMessageDTO] = [:]
    private var knownIdsAtRefreshStart: Set<Int> = []
    private var displayedAccountId: Int?
    private var displayedToken: String?
    private var requestedThreadId: Int?
    private var acceptedOptimisticIds: Set<Int> = []
    private var acceptedOptimisticProviderSids: [Int: String] = [:]
    private let fetchThread: (Int, String) async throws -> SMSThreadDTO
    private let postRead: (Int, [Int], String) async throws -> Void
    private let refreshBadge: () async -> Void
    private let currentIdentity: @MainActor () -> (accountId: Int, token: String?)
    private let snapshotCache: SMSConversationSnapshotCache
    private var readContext: ReadContext?
    private var visibleMessageIds: Set<Int> = []
    private var acknowledgedMessageIds: Set<Int> = []
    private var isAcknowledgingRead = false

    nonisolated static func readAPIRequest(threadId: Int, ids: [Int]) throws -> APIRequest {
        let body = try JSONEncoder().encode(SMSReadRequest(messageIds: ids))
        return APIRequest(path: "sms/threads/\(threadId)/read", method: .POST,
                          body: body, requiresAuth: true)
    }

    init(
        fetchThread: @escaping (Int, String) async throws -> SMSThreadDTO = { threadId, token in
            try await APIClient.shared.send(
                APIRequest(path: "sms/threads/\(threadId)", method: .GET, requiresAuth: true),
                token: token
            )
        },
        postRead: @escaping (Int, [Int], String) async throws -> Void = { threadId, ids, token in
            let response: SMSReadResponse = try await APIClient.shared.send(
                SMSThreadViewModel.readAPIRequest(threadId: threadId, ids: ids),
                token: token
            )
            guard response.ok else { throw URLError(.badServerResponse) }
        },
        refreshBadge: @escaping () async -> Void = {
            await NotificationCoordinator.shared.refreshBadgeState()
        },
        snapshotCache: SMSConversationSnapshotCache? = nil,
        currentIdentity: @escaping @MainActor () -> (accountId: Int, token: String?) = {
            (UserDefaults.standard.integer(forKey: "chatforia.currentUserId"),
             TokenStore.shared.read())
        }
    ) {
        self.fetchThread = fetchThread
        self.postRead = postRead
        self.refreshBadge = refreshBadge
        self.snapshotCache = snapshotCache ?? .shared
        self.currentIdentity = currentIdentity
        let observer = NotificationCenter.default.addObserver(
            forName: .socketSMSMessageNew,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let threadId = notification.userInfo?["threadId"] as? Int
            let messagePayload = notification.userInfo?["message"] as? [String: Any]

            Task { @MainActor [weak self] in
                guard
                    let self,
                    let threadId,
                    let messagePayload,
                    let data = try? JSONSerialization.data(withJSONObject: messagePayload),
                    let message = try? JSONDecoder.tolerantISO8601Decoder().decode(SMSMessageDTO.self, from: data)
                else { return }

                let identity = self.currentIdentity()
                guard self.requestedThreadId == threadId,
                      self.displayedAccountId == identity.accountId,
                      self.displayedToken == identity.token,
                      message.threadId == nil || message.threadId == threadId,
                      self.thread?.userId == nil ||
                      self.thread?.userId == identity.accountId else { return }

                if let sid = message.providerMessageId {
                    let confirmed = self.acceptedOptimisticProviderSids
                        .filter { $0.value == sid }.map(\.key)
                    for id in confirmed {
                        self.messages.removeAll { $0.id == id }
                        self.acceptedOptimisticIds.remove(id)
                        self.acceptedOptimisticProviderSids.removeValue(forKey: id)
                    }
                }

                let accepted: SMSMessageDTO
                if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                    accepted = Self.preferredMessage(current: self.messages[index],
                                                     incoming: message)
                    self.messages[index] = accepted
                } else {
                    accepted = message
                    self.messages.append(accepted)
                }
                if self.refreshingVersion == self.refreshVersion {
                    let previous = self.arrivalsDuringRefresh[message.id]
                    self.arrivalsDuringRefresh[message.id] = previous.map {
                        Self.preferredMessage(current: $0, incoming: accepted)
                    } ?? accepted
                }

                self.messages.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                    return $0.id < $1.id
                }
                self.cacheCurrentMessages()
            }
        }

        observers.append(observer)
    }

    private static func preferredMessage(current: SMSMessageDTO,
                                         incoming: SMSMessageDTO) -> SMSMessageDTO {
        if current.mediaRestricted && !incoming.mediaRestricted { return current }
        if incoming.mediaRestricted && !current.mediaRestricted { return incoming }
        let currentRevision = current.editedAt ?? current.createdAt
        let incomingRevision = incoming.editedAt ?? incoming.createdAt
        return incomingRevision > currentRevision ? incoming : current
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // A layout callback supplies only rows intersecting the visible scroll viewport.
    // Neither history GETs nor socket/background updates can create this context.
    func updateVisibleMessages(
        _ ids: Set<Int>, threadId: Int?, accountId: Int?, token: String?, isForeground: Bool
    ) {
        guard isForeground, let threadId, threadId > 0,
              let accountId, accountId > 0,
              let token, !token.isEmpty,
              currentIdentity().accountId == accountId,
              currentIdentity().token == token else {
            readContext = nil
            visibleMessageIds = []
            return
        }
        let next = ReadContext(threadId: threadId, accountId: accountId, token: token)
        if readContext != next { acknowledgedMessageIds = [] }
        readContext = next
        visibleMessageIds = ids
    }

    func acknowledgeVisibleMessages() async {
        guard !isAcknowledgingRead else { return }
        isAcknowledgingRead = true
        defer { isAcknowledgingRead = false }
        while let context = readContext {
            let identity = currentIdentity()
            guard identity.accountId == context.accountId,
                  identity.token == context.token,
                  thread?.id == context.threadId,
                  thread?.userId == nil || thread?.userId == context.accountId else { return }
            let ids = messages.filter {
                $0.id > 0 && $0.isIncoming &&
                ($0.threadId == nil || $0.threadId == context.threadId) &&
                visibleMessageIds.contains($0.id) &&
                !acknowledgedMessageIds.contains($0.id)
            }.map(\.id).prefix(100).map { $0 }
            guard !ids.isEmpty else { return }

            do {
                try await postRead(context.threadId, ids, context.token)
            } catch {
                // Keep unread state intact. The next visible layout, refresh, or
                // foreground transition retries the same exact IDs.
                if readContext != context { continue }
                return
            }

            let current = currentIdentity()
            guard readContext == context,
                  current.accountId == context.accountId,
                  current.token == context.token else { continue }
            acknowledgedMessageIds.formUnion(ids)
            NotificationCenter.default.post(
                name: Notification.Name("smsThreadWasRead"), object: nil,
                userInfo: ["threadId": context.threadId, "accountId": context.accountId]
            )
            await refreshBadge()
        }
    }
    
    func loadThread(threadId: Int, token: String?,
                    acceptedOptimisticId: Int? = nil,
                    acceptedProviderMessageId: String? = nil) async {
        refreshVersion += 1
        let requestVersion = refreshVersion
        let identity = currentIdentity()
        let accountId = identity.accountId
        guard let token, !token.isEmpty, accountId > 0,
              identity.token == token else {
            isLoading = false
            thread = nil
            messages = []
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return
        }

        if displayedAccountId != accountId || displayedToken != token ||
            requestedThreadId != threadId {
            let acceptedRow = acceptedOptimisticId.flatMap { id in
                messages.first { $0.id == id && id < 0 }
            }
            thread = nil
            messages = acceptedRow.map { [$0] } ?? []
            acceptedOptimisticIds = []
            acceptedOptimisticProviderSids = [:]
            readContext = nil
            visibleMessageIds = []
            acknowledgedMessageIds = []
        }
        if let acceptedOptimisticId {
            acceptedOptimisticIds.insert(acceptedOptimisticId)
            if let acceptedProviderMessageId, !acceptedProviderMessageId.isEmpty {
                acceptedOptimisticProviderSids[acceptedOptimisticId] = acceptedProviderMessageId
            }
        }
        displayedAccountId = accountId
        displayedToken = token
        requestedThreadId = threadId
        let cached = snapshotCache.snapshot(accountId: accountId, threadId: threadId)
        if thread == nil, let cached {
            thread = cached.thread
            messages = cached.messages
        }
        // A cached empty thread is a real snapshot, not an initial loading state.
        isLoading = thread == nil
        arrivalsDuringRefresh = [:]
        knownIdsAtRefreshStart = Set(messages.filter { $0.id > 0 }.map(\.id))
        refreshingVersion = requestVersion
        errorText = nil
        defer {
            if requestVersion == refreshVersion {
                refreshingVersion = nil
                arrivalsDuringRefresh = [:]
                knownIdsAtRefreshStart = []
                isLoading = false
            }
        }

        do {
            let fetched = try await fetchThread(threadId, token)

            guard requestVersion == refreshVersion, !Task.isCancelled,
                  currentIdentity().token == token,
                  currentIdentity().accountId == accountId,
                  fetched.id == threadId,
                  fetched.userId == nil || fetched.userId == accountId else { return }

            thread = fetched
            var byId: [Int: SMSMessageDTO] = [:]
            for message in fetched.sortedMessages { byId[message.id] = message }
            // A server window can lag a revision already delivered by the
            // socket. Keep newer fields for IDs the server still authorizes;
            // rows omitted by the server are never retained from the cache.
            for previous in messages where previous.id > 0 {
                if let server = byId[previous.id] {
                    byId[previous.id] = Self.preferredMessage(current: server,
                                                               incoming: previous)
                }
            }
            for (id, arrival) in arrivalsDuringRefresh {
                if let server = byId[id] {
                    byId[id] = Self.preferredMessage(current: server,
                                                     incoming: arrival)
                } else if !knownIdsAtRefreshStart.contains(id) {
                    byId[id] = arrival
                }
            }
            let pending = messages.filter {
                $0.id <= 0 && $0.threadId == threadId &&
                !acceptedOptimisticIds.contains($0.id)
            }
            messages = snapshotCache.excludingRemoved(Array(byId.values) + pending,
                                                      accountId: accountId, threadId: threadId)
                .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
            acceptedOptimisticIds.removeAll()
            acceptedOptimisticProviderSids.removeAll()
            cacheCurrentMessages()
            errorText = nil

            // A GET is read-only. Only IDs reported by the foreground scroll
            // viewport may be acknowledged by the explicit POST endpoint.
            await acknowledgeVisibleMessages()
        } catch {
            guard requestVersion == refreshVersion, !Task.isCancelled,
                  currentIdentity().token == token,
                  currentIdentity().accountId == accountId,
                  !isCancelledRefresh(error) else { return }

            if isAuthorizationFailure(error) {
                snapshotCache.remove(accountId: accountId, threadId: threadId)
                thread = nil
                messages = []
                requestedThreadId = nil
                readContext = nil
                visibleMessageIds = []
                errorText = friendlyErrorMessage(error)
            } else if messages.isEmpty {
                errorText = friendlyErrorMessage(error)
            } else {
                errorText = appText(
                    "sms.refreshFailed",
                    languageCode: appLanguage
                )
            }

        }
    }

    private func cacheCurrentMessages() {
        guard let thread, let accountId = displayedAccountId,
              requestedThreadId == thread.id,
              currentIdentity().accountId == accountId,
              currentIdentity().token == displayedToken else { return }
        snapshotCache.store(thread: thread, messages: messages, accountId: accountId)
    }

    private func isAuthorizationFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .unauthorized: return true
        case .server(let status, _, _, _): return status == 401 || status == 403
        default: return false
        }
    }

    // APIClient wraps URLSession cancellation in APIError.network.
    // Cancellation is expected when leaving or restarting a refresh.
    private func isCancelledRefresh(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let apiError = error as? APIError,
           case .network(let underlying) = apiError {
            return isCancelledRefresh(underlying)
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    func sendTextMessage(
        existingThreadId: Int?,
        to: String,
        text: String,
        token: String?
    ) async -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return nil
        }

        let sendAccountId = currentIdentity().accountId

        isSending = true
        errorText = nil

        let optimisticThreadId = existingThreadId ?? -1
        let optimistic = SMSMessageDTO.optimisticOutgoing(
            threadId: optimisticThreadId,
            to: to,
            body: trimmed
        )

        messages.append(optimistic)
        messages.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }

        struct SendSMSRequest: Encodable {
            let to: String
            let body: String
        }

        do {
            let body = try JSONEncoder().encode(
                SendSMSRequest(to: to, body: trimmed)
            )

            let response: SendSMSResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "sms/send", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            isSending = false

            // An accepted send is represented by the canonical server row on
            // the next successful history response. Keep the local row only
            // while that response is unavailable.
            let identity = currentIdentity()
            guard identity.token == token,
                  identity.accountId == sendAccountId,
                  identity.accountId > 0 else { return nil }
            
            AnalyticsManager.shared.capture("sms_sent", properties: [
                "type": "text"
            ])
            
            await loadThread(threadId: response.threadId, token: token,
                             acceptedOptimisticId: optimistic.id,
                             acceptedProviderMessageId: response.messageSid)
            return response.threadId
        } catch {
            isSending = false
            messages.removeAll { $0.id == optimistic.id }
            errorText = friendlyErrorMessage(error)
            return nil
        }
    }

    func sendMediaMessage(
        existingThreadId: Int?,
        to: String,
        mediaUrls: [String],
        token: String?
    ) async -> Int? {
        guard !mediaUrls.isEmpty else { return nil }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return nil
        }

        isSending = true
        errorText = nil

        struct SendSMSMediaRequest: Encodable {
            let to: String
            let body: String?
            let mediaUrls: [String]
        }

        do {
            let body = try JSONEncoder().encode(
                SendSMSMediaRequest(to: to, body: nil, mediaUrls: mediaUrls)
            )

            let response: SendSMSResponseDTO = try await APIClient.shared.send(
                APIRequest(path: "sms/send", method: .POST, body: body, requiresAuth: true),
                token: token
            )

            guard response.ok, response.threadId > 0 else {
                throw URLError(.badServerResponse)
            }
            isSending = false
            
            AnalyticsManager.shared.capture("sms_sent", properties: [
                "type": "media"
            ])
            
            await loadThread(threadId: response.threadId, token: token)
            return response.threadId
        } catch {
            isSending = false
            errorText = friendlyErrorMessage(error)
            return nil
        }
    }

    func deleteMessage(
        messageId: Int,
        token: String?
    ) async {
        guard messageId > 0 else {
            messages.removeAll { $0.id == messageId }
            return
        }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return
        }

        errorText = nil

        do {
            let _: DeleteSMSMessageResponse =
                try await APIClient.shared.send(
                    APIRequest(
                        path: "sms/messages/\(messageId)",
                        method: .DELETE,
                        requiresAuth: true
                    ),
                    token: token
                )

            guard currentIdentity().token == token,
                  currentIdentity().accountId == displayedAccountId else { return }
            messages.removeAll { $0.id == messageId }
            if let thread, let accountId = displayedAccountId {
                snapshotCache.removeMessage(messageId, accountId: accountId, threadId: thread.id)
                cacheCurrentMessages()
            }

            AnalyticsManager.shared.capture(
                "sms_message_deleted_for_me",
                properties: [
                    "messageId": messageId
                ]
            )
        } catch {
            errorText = friendlyErrorMessage(error)
        }
    }

    func reportMessage(
        messageId: Int,
        reason: ReportReason,
        details: String,
        contextCount: Int,
        blockAfterReport: Bool,
        token: String?
    ) async -> Bool {
        guard messageId > 0 else { return false }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return false
        }

        errorText = nil

        do {
            let trimmedDetails =
                details
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            let body = try JSONEncoder().encode(
                ReportPSTNMessageRequest(
                    reason: reason.rawValue,
                    details: trimmedDetails.isEmpty ? nil : trimmedDetails,
                    contextCount: max(0, min(contextCount, 20)),
                    blockAfterReport: blockAfterReport
                )
            )

            let response: ReportPSTNMessageResponse =
                try await APIClient.shared.send(
                    APIRequest(
                        path: "sms/messages/\(messageId)/report",
                        method: .POST,
                        body: body,
                        requiresAuth: true
                    ),
                    token: token
                )

            guard response.success else {
                errorText = "Failed to submit report."
                return false
            }

            AnalyticsManager.shared.capture(
                "sms_message_reported",
                properties: [
                    "messageId": messageId,
                    "reason": reason.rawValue,
                    "blockAfterReport": blockAfterReport
                ]
            )

            return true
        } catch {
            errorText = friendlyErrorMessage(error)
            return false
        }
    }

    func blockNumber(
        phone: String,
        token: String?
    ) async -> Bool {
        let normalizedPhone =
            phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPhone.isEmpty else {
            errorText = "Missing phone number."
            return false
        }

        guard let token else {
            errorText = appText(
                "ios.missing_auth_token",
                languageCode: appLanguage
            )
            return false
        }

        errorText = nil

        do {
            let body = try JSONEncoder().encode(
                BlockPSTNNumberRequest(phone: normalizedPhone)
            )

            let response: BlockPSTNNumberResponse =
                try await APIClient.shared.send(
                    APIRequest(
                        path: "sms/blocked-numbers",
                        method: .POST,
                        body: body,
                        requiresAuth: true
                    ),
                    token: token
                )

            guard response.success else {
                errorText = "Failed to block number."
                return false
            }

            AnalyticsManager.shared.capture(
                "sms_number_blocked",
                properties: [
                    "phone": normalizedPhone
                ]
            )

            return true
        } catch {
            errorText = friendlyErrorMessage(error)
            return false
        }
    }

    func resolvedTitle(fallback conversationTitle: String, fallbackPhone: String?) -> String {
        if let preferred = thread?.resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return preferred
        }

        if let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return title
        }

        if let phone = fallbackPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return phone
        }

        if let id = thread?.id {
            return "SMS #\(id)"
        }

        return "SMS"
    }

    func resolvedPhone(fallback conversationPhone: String?) -> String? {
        thread?.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        ?? conversationPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .server(let status, let code, _, _):
            if code == "TEEN_VISUAL_MEDIA_RESTRICTED" {
                return appText("messages.teenMediaRestricted", languageCode: appLanguage,
                               fallback: "Images and videos are unavailable in conversations involving teen accounts.")
            }
            if code == "SMS_OPTED_OUT" {
                return "This number has opted out of SMS. " +
                    "They must reply START before you can message them again."
            }

            if status >= 500 {
                return "Server temporarily unavailable. Please try again."
            }

            return "Something went wrong. Please try again."

        case .network:
            return "Network connection issue. Please check your connection and try again."

        case .unauthorized:
            return appText(
                "api.notAuthorized",
                languageCode: appLanguage
            )

        default:
            return "Something went wrong. Please try again."
        }
    }

    return "Something went wrong. Please try again."
}
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
