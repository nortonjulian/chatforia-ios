import Foundation

extension Notification.Name {
    static let DeliveryStateChanged = Notification.Name("Chatforia.DeliveryStateChanged")
    static let MessagesChanged = Notification.Name("Chatforia.MessagesChanged")
}

final class MessageStore {
    static let shared = MessageStore()

    // Optional mapper hook — if your codebase knows how to convert ServerMessage -> MessageDTO,
    // set this closure (e.g., in your DTO file or app startup). If not set, insertOrReplace(ServerMessage) is a no-op.
    static var serverToDTOMapper: ((MessageDTO) -> MessageDTO)? = nil

    private var deliveryStates: [String: DeliveryState] = [:]
    private var messages: [MessageDTO] = []
    private let lock = DispatchQueue(label: "chatforia.messageStore.lock", attributes: .concurrent)

    private let tombstoneKey = "Chatforia_OldestRemovedMessageId"
    private(set) var oldestRemovedMessageId: Int? {
        didSet {
            if let id = oldestRemovedMessageId {
                UserDefaults.standard.set(id, forKey: tombstoneKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tombstoneKey)
            }
        }
    }

    private let inMemoryMax = 500

    private let deliveryStatesFileURL: URL = {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return doc.appendingPathComponent("message_delivery_states.json")
    }()

    private let messagesFileURL: URL = {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return doc.appendingPathComponent("message_window.json")
    }()

    private init() {
        if UserDefaults.standard.object(forKey: tombstoneKey) != nil {
            self.oldestRemovedMessageId = UserDefaults.standard.integer(forKey: tombstoneKey)
        } else {
            self.oldestRemovedMessageId = nil
        }

        loadPersistedState()
    }

    private func loadPersistedState() {
        lock.async(flags: .barrier) {
            do {
                let deliveryData = try Data(contentsOf: self.deliveryStatesFileURL)
                self.deliveryStates = try JSONDecoder().decode([String: DeliveryState].self, from: deliveryData)
            } catch {
                self.deliveryStates = [:]
            }

            do {
                let messageData = try Data(contentsOf: self.messagesFileURL)
                self.messages = try JSONDecoder().decode([MessageDTO].self, from: messageData)
                self.sortMessagesLocked()
                self.messages = self.dedupeMessages(self.messages)
                self.capInMemoryMessagesLocked(max: self.inMemoryMax)
            } catch {
                self.messages = []
            }
        }
    }

    // MARK: - Scoring / merge helpers

    private func completenessScore(_ message: MessageDTO) -> Int {
        var score = 0

        if let raw = message.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 2
        }

        if let readBy = message.readBy, !readBy.isEmpty {
            score += 1
        }

        if let reactionSummary = message.reactionSummary, !reactionSummary.isEmpty {
            score += 1
        }

        if message.expiresAt != nil {
            score += 1
        }

        if message.editedAt != nil {
            score += 1
        }

        if message.deletedAt != nil || message.deletedForAll == true || message.deletedBySender == true {
            score += 1
        }

        if message.imageUrl != nil {
            score += 1
        }

        if message.audioUrl != nil {
            score += 1
        }

        return score
    }

    private func normalizedClientMessageId(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func rank(_ s: DeliveryState) -> Int {
        switch s {
        case .failed: return -1
        case .pending: return 0
        case .sending: return 1
        case .sent: return 2
        case .delivered: return 3
        case .read: return 4
        }
    }
    
    private func preferredMessage(existing: MessageDTO, incoming: MessageDTO) -> MessageDTO {
        let existingRevision = existing.revision ?? 0
        let incomingRevision = incoming.revision ?? 0

        if incomingRevision > existingRevision {
            return mergedMessage(preferred: incoming, fallback: existing)
        }

        if incomingRevision < existingRevision {
            return mergedMessage(preferred: existing, fallback: incoming)
        }

        let existingScore = completenessScore(existing)
        let incomingScore = completenessScore(incoming)

        if incomingScore >= existingScore {
            return mergedMessage(preferred: incoming, fallback: existing)
        } else {
            return mergedMessage(preferred: existing, fallback: incoming)
        }
    }

    private func mergedMessage(preferred: MessageDTO, fallback: MessageDTO) -> MessageDTO {
        MessageDTO(
            id: preferred.id,
            contentCiphertext: preferred.contentCiphertext ?? fallback.contentCiphertext,
            rawContent: preferred.rawContent ?? fallback.rawContent,
            translations: preferred.translations ?? fallback.translations,
            translatedFrom: preferred.translatedFrom ?? fallback.translatedFrom,
            translatedForMe: preferred.translatedForMe ?? fallback.translatedForMe,
            encryptedKeyForMe: preferred.encryptedKeyForMe ?? fallback.encryptedKeyForMe,
            imageUrl: preferred.imageUrl ?? fallback.imageUrl,
            audioUrl: preferred.audioUrl ?? fallback.audioUrl,
            audioDurationSec: preferred.audioDurationSec ?? fallback.audioDurationSec,
            isExplicit: preferred.isExplicit ?? fallback.isExplicit,
            createdAt: preferred.createdAt,
            expiresAt: preferred.expiresAt ?? fallback.expiresAt,
            editedAt: preferred.editedAt ?? fallback.editedAt,
            deletedBySender: preferred.deletedBySender,
            deletedForAll: preferred.deletedForAll,
            deletedAt: preferred.deletedAt ?? fallback.deletedAt,
            deletedById: preferred.deletedById ?? fallback.deletedById,
            sender: preferred.sender,
            readBy: !(preferred.readBy?.isEmpty ?? true) ? preferred.readBy : fallback.readBy,
            chatRoomId: preferred.chatRoomId,
            reactionSummary: !(preferred.reactionSummary?.isEmpty ?? true) ? preferred.reactionSummary : fallback.reactionSummary,
            myReactions: !(preferred.myReactions?.isEmpty ?? true) ? preferred.myReactions : fallback.myReactions,
            revision: max(preferred.revision ?? 0, fallback.revision ?? 0),
            clientMessageId: preferred.clientMessageId ?? fallback.clientMessageId
        )
    }

    private func sortMessagesLocked() {
        self.messages.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    /// Canonical dedupe:
    /// 1. Prefer clientMessageId reconciliation when present.
    /// 2. Otherwise reconcile by server id.
    /// 3. Merge collisions instead of blindly replacing.
    private func dedupeMessages(_ source: [MessageDTO]) -> [MessageDTO] {
        var result: [MessageDTO] = []
        var indexByClientId: [String: Int] = [:]
        var indexByServerId: [Int: Int] = [:]

        for message in source {
            let incomingClientId = normalizedClientMessageId(message.clientMessageId)

            if let incomingClientId,
               let existingIndex = indexByClientId[incomingClientId] {
                let existing = result[existingIndex]
                let merged = preferredMessage(existing: existing, incoming: message)
                result[existingIndex] = merged

                indexByServerId[merged.id] = existingIndex
                if let mergedClientId = normalizedClientMessageId(merged.clientMessageId) {
                    indexByClientId[mergedClientId] = existingIndex
                }
                continue
            }

            if let existingIndex = indexByServerId[message.id] {
                let existing = result[existingIndex]
                let merged = preferredMessage(existing: existing, incoming: message)
                result[existingIndex] = merged

                indexByServerId[merged.id] = existingIndex
                if let mergedClientId = normalizedClientMessageId(merged.clientMessageId) {
                    indexByClientId[mergedClientId] = existingIndex
                }
                continue
            }

            let newIndex = result.count
            result.append(message)
            indexByServerId[message.id] = newIndex
            if let incomingClientId {
                indexByClientId[incomingClientId] = newIndex
            }
        }

        return result
    }

    private func notifyMessagesChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .MessagesChanged, object: nil)
        }
    }

    private func persistStateLocked() {
        do {
            let deliveryData = try JSONEncoder().encode(self.deliveryStates)
            try deliveryData.write(to: self.deliveryStatesFileURL, options: Data.WritingOptions.atomic)
        } catch {
            print("❌ Failed to persist delivery states:", error)
        }

        do {
            let recentMessages = Array(self.messages.suffix(200))
            let messageData = try JSONEncoder().encode(recentMessages)
            try messageData.write(to: self.messagesFileURL, options: Data.WritingOptions.atomic)
        } catch {
            print("❌ Failed to persist message window:", error)
        }
    }

    // MARK: - Delivery state

    func setDeliveryState(clientMessageId: String, state: DeliveryState) {
        guard !clientMessageId.isEmpty else { return }

        lock.async(flags: .barrier) {
            if let currentState = self.deliveryStates[clientMessageId],
               self.rank(state) < self.rank(currentState) {
                return
            }

            self.deliveryStates[clientMessageId] = state
            self.persistStateLocked()

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .DeliveryStateChanged,
                    object: nil,
                    userInfo: ["clientMessageId": clientMessageId, "state": state.rawValue]
                )
            }
        }
    }

    func getDeliveryState(clientMessageId: String) -> DeliveryState? {
        guard !clientMessageId.isEmpty else { return nil }
        var result: DeliveryState?
        lock.sync {
            result = self.deliveryStates[clientMessageId]
        }
        return result
    }

    func markDeliveryState(clientMessageId: String, state: DeliveryState) {
        setDeliveryState(clientMessageId: clientMessageId, state: state)
    }

    func markMessageRead(messageId: Int) {
        guard let msg = messages.first(where: { $0.id == messageId }),
              let cid = msg.clientMessageId else { return }

        markDeliveryState(clientMessageId: cid, state: .read)
    }

    // MARK: - In-memory window access

    func currentWindow() -> [MessageDTO] {
        var snapshot: [MessageDTO] = []
        lock.sync {
            snapshot = self.messages
        }
        return snapshot
    }

    func newestMessageId() -> Int? {
        lock.sync {
            messages.last?.id
        }
    }

    func oldestMessageId() -> Int? {
        lock.sync {
            messages.first?.id
        }
    }

    // MARK: - Upsert hooks

    /// Convert ServerMessage -> MessageDTO then batch upsert.
    /// Uses `MessageStore.serverToDTOMapper` if provided; otherwise does nothing.
    func insertOrReplace(_ serverMessage: MessageDTO?) {
        guard let msg = serverMessage else { return }

        insertOrReplace([msg])

        if let clientId = msg.clientMessageId, !clientId.isEmpty {
            setDeliveryState(clientMessageId: clientId, state: .sent)
        } else {
            let serverKey = "server:\(msg.id)"
            setDeliveryState(clientMessageId: serverKey, state: .sent)
        }
    }

    /// Already-decoded MessageDTO variant
    func insertOrReplaceServerMessage(_ serverMessage: MessageDTO?) {
        guard let dto = serverMessage else { return }
        insertOrReplace([dto])

        if let clientId = dto.clientMessageId, !clientId.isEmpty {
            setDeliveryState(clientMessageId: clientId, state: .sent)
        } else {
            let serverKey = "server:\(dto.id)"
            setDeliveryState(clientMessageId: serverKey, state: .sent)
        }
    }

    /// Batch upsert (socket batch or page)
    func insertOrReplace(_ incoming: [MessageDTO]) {
        guard !incoming.isEmpty else { return }

        lock.async(flags: .barrier) {
            for inc in incoming {
                let incomingClientId = self.normalizedClientMessageId(inc.clientMessageId)

                let existingIndex = self.messages.firstIndex { existing in
                    let existingClientId = self.normalizedClientMessageId(existing.clientMessageId)

                    if let incomingClientId, existingClientId == incomingClientId {
                        return true
                    }

                    return existing.id == inc.id
                }

                if let idx = existingIndex {
                    let existing = self.messages[idx]
                    self.messages[idx] = self.preferredMessage(existing: existing, incoming: inc)
                } else {
                    self.messages.append(inc)
                }
            }

            self.sortMessagesLocked()
            self.messages = self.dedupeMessages(self.messages)
            self.capInMemoryMessagesLocked(max: self.inMemoryMax)
            self.persistStateLocked()
            self.notifyMessagesChanged()
        }
    }

    // MARK: - Trimming / tombstone

    func capInMemoryMessages(max: Int = 500) {
        guard max > 0 else { return }

        lock.async(flags: .barrier) {
            self.capInMemoryMessagesLocked(max: max)
            self.persistStateLocked()
            self.notifyMessagesChanged()
        }
    }

    private func capInMemoryMessagesLocked(max: Int) {
        guard max > 0 else { return }
        guard self.messages.count > max else { return }

        let toRemoveCount = self.messages.count - max
        let removedPrefix = Array(self.messages.prefix(toRemoveCount))

        // Keep the newest removed id as the paging tombstone boundary.
        if let newestRemovedId = removedPrefix.last?.id {
            self.oldestRemovedMessageId = newestRemovedId
        }

        self.messages.removeFirst(toRemoveCount)
    }

    // MARK: - Paging helpers

    func serverBeforeIdForPaging() -> Int? {
        var id: Int?
        lock.sync {
            if let oldestInMemory = self.messages.first?.id {
                id = oldestInMemory
            } else {
                id = self.oldestRemovedMessageId
            }
        }
        return id
    }

    // MARK: - Convenience

    func replaceOptimisticMessage(clientMessageId: String, with serverDTO: MessageDTO) {
        guard !clientMessageId.isEmpty else { return }

        lock.async(flags: .barrier) {
            if let idx = self.messages.firstIndex(where: {
                self.normalizedClientMessageId($0.clientMessageId) == clientMessageId || $0.id == serverDTO.id
            }) {
                let existing = self.messages[idx]
                self.messages[idx] = self.preferredMessage(existing: existing, incoming: serverDTO)
            } else {
                self.messages.append(serverDTO)
            }

            self.sortMessagesLocked()
            self.messages = self.dedupeMessages(self.messages)
            self.capInMemoryMessagesLocked(max: self.inMemoryMax)
            self.persistStateLocked()
            self.notifyMessagesChanged()
        }

        setDeliveryState(clientMessageId: clientMessageId, state: .sent)
    }
}
