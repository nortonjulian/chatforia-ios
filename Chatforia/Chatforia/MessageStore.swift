import Foundation

extension Notification.Name {
    static let DeliveryStateChanged = Notification.Name("Chatforia.DeliveryStateChanged")
    static let MessagesChanged = Notification.Name("Chatforia.MessagesChanged")
}

final class MessageStore {
    static let shared = MessageStore()

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

    // MARK: - Persistence

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
                self.capInMemoryMessagesLocked(limit: self.inMemoryMax)
            } catch {
                self.messages = []
            }
        }
    }

    private func persistLocked() {
        do {
            let deliveryData = try JSONEncoder().encode(deliveryStates)
            try deliveryData.write(to: deliveryStatesFileURL, options: .atomic)
        } catch {
            print("❌ MessageStore persist deliveryStates failed:", error)
        }

        do {
            let messageData = try JSONEncoder().encode(messages)
            try messageData.write(to: messagesFileURL, options: .atomic)
        } catch {
            print("❌ MessageStore persist messages failed:", error)
        }
    }

    private func postMessagesChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .MessagesChanged, object: nil)
        }
    }

    private func postDeliveryStateChanged(clientMessageId: String, state: DeliveryState) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .DeliveryStateChanged,
                object: nil,
                userInfo: [
                    "clientMessageId": clientMessageId,
                    "state": state.rawValue
                ]
            )
        }
    }

    // MARK: - Scoring / merge helpers

    private func completenessScore(_ message: MessageDTO) -> Int {
        var score = 0

        if let raw = message.rawContent,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 2
        }

        if let translated = message.translatedForMe,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 2
        }

        if let readBy = message.readBy, !readBy.isEmpty {
            score += 1
        }

        if let reactionSummary = message.reactionSummary, !reactionSummary.isEmpty {
            score += 1
        }

        if let myReactions = message.myReactions, !myReactions.isEmpty {
            score += 1
        }

        if let attachments = message.attachments, !attachments.isEmpty {
            score += 2
        }

        if message.imageUrl != nil { score += 1 }
        if message.audioUrl != nil { score += 1 }
        if message.audioDurationSec != nil { score += 1 }

        if message.expiresAt != nil { score += 1 }
        if message.editedAt != nil { score += 1 }
        if message.deletedAt != nil { score += 1 }
        if message.deletedForAll == true { score += 2 }

        if let ciphertext = message.contentCiphertext, !ciphertext.isEmpty {
            score += 1
        }
        if let key = message.encryptedKeyForMe, !key.isEmpty {
            score += 1
        }

        let revision = message.revision ?? 0
        score += revision

        return score
    }

    private func preferredMessage(current: MessageDTO, incoming: MessageDTO) -> MessageDTO {

        // 🚨 HARD OVERRIDE: deletion always wins
        if incoming.deletedForAll == true || incoming.deletedAt != nil {
            return MessageDTO.merged(current: current, incoming: incoming)
        }

        // 🚨 HARD OVERRIDE: edits always win
        if incoming.editedAt != nil {
            return MessageDTO.merged(current: current, incoming: incoming)
        }

        let currentScore = completenessScore(current)
        let incomingScore = completenessScore(incoming)

        if incomingScore > currentScore {
            return incoming
        }

        return MessageDTO.merged(current: current, incoming: incoming)
    }

    // MARK: - Sort / dedupe / cap

    private func sortMessagesLocked() {
        self.messages.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    private func dedupeMessages(_ source: [MessageDTO]) -> [MessageDTO] {
        var seenServerIds = Set<Int>()
        var seenClientIds = Set<String>()
        var result: [MessageDTO] = []

        for msg in source {
            if msg.id > 0 {
                if seenServerIds.contains(msg.id) { continue }
                seenServerIds.insert(msg.id)
                result.append(msg)
                continue
            }

            if let cid = msg.clientMessageId, !cid.isEmpty {
                if seenClientIds.contains(cid) { continue }
                seenClientIds.insert(cid)
                result.append(msg)
                continue
            }

            result.append(msg)
        }

        return result
    }

    private func capInMemoryMessagesLocked(limit: Int) {
        guard messages.count > limit else { return }

        let overflow = messages.count - limit
        let removed = messages.prefix(overflow)

        if let maxRemovedServerId = removed.map(\.id).filter({ $0 > 0 }).max() {
            oldestRemovedMessageId = Swift.max(oldestRemovedMessageId ?? 0, maxRemovedServerId)
        }

        messages.removeFirst(overflow)
    }

    func removeMessages(forRoomId roomId: Int) {
        lock.async(flags: .barrier) {
            self.messages.removeAll { $0.chatRoomId == roomId }
            self.persistLocked()
            self.postMessagesChanged()
        }
    }

    func deliveryState(for clientMessageId: String) -> DeliveryState? {
        lock.sync {
            deliveryStates[clientMessageId]
        }
    }

    func setDeliveryState(clientMessageId: String, state: DeliveryState) {
        lock.async(flags: .barrier) {
            self.deliveryStates[clientMessageId] = state
            self.persistLocked()
            self.postDeliveryStateChanged(clientMessageId: clientMessageId, state: state)
        }
    }

    // MARK: - Core upsert

    func upsertMessage(_ incoming: MessageDTO) {
        lock.async(flags: .barrier) {
            self.upsertMessageLocked(incoming)
            self.persistLocked()
            self.postMessagesChanged()
        }
    }

    func upsertMany(_ incoming: [MessageDTO]) {
        guard !incoming.isEmpty else { return }

        lock.async(flags: .barrier) {
            for msg in incoming {
                self.upsertMessageLocked(msg)
            }
            self.persistLocked()
            self.postMessagesChanged()
        }
    }

    func insertOrReplace(_ incoming: MessageDTO) {
        upsertMessage(incoming)
    }

    func insertOrReplace(_ incoming: [MessageDTO]) {
        upsertMany(incoming)
    }

    func insertOrReplaceSync(_ incoming: [MessageDTO]) {
        guard !incoming.isEmpty else { return }

        lock.sync(flags: .barrier) {
            for msg in incoming {
                self.upsertMessageLocked(msg)
            }
            self.persistLocked()
        }

        postMessagesChanged()
    }

    private func upsertMessageLocked(_ incoming: MessageDTO) {
        if let idx = self.messages.firstIndex(where: {
            ($0.id > 0 && incoming.id > 0 && $0.id == incoming.id) ||
            ($0.clientMessageId != nil &&
             incoming.clientMessageId != nil &&
             $0.clientMessageId == incoming.clientMessageId)
        }) {
            let existing = self.messages[idx]
            let updated = self.preferredMessage(current: existing, incoming: incoming)

            self.messages[idx] = updated
        } else {
            self.messages.append(incoming)
        }

        self.sortMessagesLocked()
        self.messages = self.dedupeMessages(self.messages)
        self.capInMemoryMessagesLocked(limit: self.inMemoryMax)
    }

    // MARK: - Optimistic replacement

    func replaceOptimisticMessage(clientMessageId: String, with serverMessage: MessageDTO) {
        lock.async(flags: .barrier) {
            if let idx = self.messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
                let existing = self.messages[idx]

                let normalized = MessageDTO.merged(
                    current: existing,
                    incoming: MessageDTO(
                        id: serverMessage.id,
                        contentCiphertext: serverMessage.contentCiphertext,
                        rawContent: serverMessage.rawContent,
                        translations: serverMessage.translations,
                        translatedFrom: serverMessage.translatedFrom,
                        translatedForMe: serverMessage.translatedForMe,
                        encryptedKeyForMe: serverMessage.encryptedKeyForMe,
                        imageUrl: serverMessage.imageUrl,
                        audioUrl: serverMessage.audioUrl,
                        audioDurationSec: serverMessage.audioDurationSec,
                        attachments: serverMessage.attachments,
                        isExplicit: serverMessage.isExplicit,
                        createdAt: serverMessage.createdAt,
                        expiresAt: serverMessage.expiresAt,
                        editedAt: serverMessage.editedAt,
                        deletedBySender: serverMessage.deletedBySender,
                        deletedForAll: serverMessage.deletedForAll,
                        deletedAt: serverMessage.deletedAt,
                        deletedById: serverMessage.deletedById,
                        sender: serverMessage.sender,
                        readBy: serverMessage.readBy,
                        chatRoomId: serverMessage.chatRoomId,
                        reactionSummary: serverMessage.reactionSummary,
                        myReactions: serverMessage.myReactions,
                        revision: serverMessage.revision,
                        clientMessageId: serverMessage.clientMessageId ?? clientMessageId
                    )
                )

                self.messages[idx] = normalized
            } else {
                self.messages.append(serverMessage)
            }

            self.sortMessagesLocked()
            self.messages = self.dedupeMessages(self.messages)
            self.capInMemoryMessagesLocked(limit: self.inMemoryMax)
            self.persistLocked()
            self.postMessagesChanged()
        }
    }

    // MARK: - Read

    func currentWindow() -> [MessageDTO] {
        lock.sync {
            self.messages
        }
    }

    func message(withId id: Int) -> MessageDTO? {
        lock.sync {
            self.messages.first(where: { $0.id == id })
        }
    }

    func serverBeforeIdForPaging() -> Int? {
        lock.sync {
            let serverIds = self.messages.map(\.id).filter { $0 > 0 }
            return serverIds.min()
        }
    }

    // MARK: - Remove

    func removeMessage(id: Int) {
        lock.async(flags: .barrier) {
            if id > 0 {
                self.oldestRemovedMessageId = max(self.oldestRemovedMessageId ?? 0, id)
            }

            self.messages.removeAll { $0.id == id }
            self.persistLocked()
            self.postMessagesChanged()
        }
    }

    func clearAll() {
        lock.async(flags: .barrier) {
            self.messages.removeAll()
            self.deliveryStates.removeAll()
            self.oldestRemovedMessageId = nil
            self.persistLocked()
            self.postMessagesChanged()
        }
    }
}
