// MessageStore.swift
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

    private func completenessScore(_ message: MessageDTO) -> Int {
        var score = 0

        if let raw = message.rawContent,
           !raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
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

        return score
    }
    

    func setDeliveryState(clientMessageId: String, state: DeliveryState) {
        guard !clientMessageId.isEmpty else { return }

        lock.async(flags: .barrier) {
            self.deliveryStates[clientMessageId] = state
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
            return messages.last?.id
        }
    }

    func oldestMessageId() -> Int? {
        lock.sync {
            return messages.first?.id
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
            // dto.id is non-optional in your DTO; use it directly
            let serverKey = "server:\(dto.id)"
            setDeliveryState(clientMessageId: serverKey, state: .sent)
        }
    }

    /// Batch upsert (socket batch or page)
    func insertOrReplace(_ incoming: [MessageDTO]) {
        guard !incoming.isEmpty else { return }

        lock.async(flags: .barrier) {
            var existingById: [Int: Int] = [:]
            var existingByClientId: [String: Int] = [:]

            for (i, m) in self.messages.enumerated() {
                // m.id is an Int in your DTO; use it directly
                existingById[m.id] = i
                if let client = m.clientMessageId, !client.isEmpty { existingByClientId[client] = i }
            }

            for inc in incoming {
                var replaced = false

                // inc.id is Int (non-optional); use direct lookup
                let incId = inc.id
                if let idx = existingById[incId] {
                    self.messages[idx] = inc
                    replaced = true
                } else if let client = inc.clientMessageId, !client.isEmpty, let idx = existingByClientId[client] {
                    self.messages[idx] = inc
                    replaced = true
                }

                if !replaced {
                    self.messages.append(inc)
                }
            }

            // Sort by createdAt then dedupe
            self.messages.sort {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id < $1.id
            }

            var seenServerIds = Set<Int>()
            var seenClientIds = Set<String>()
            var deduped: [MessageDTO] = []
            for m in self.messages {
                let id = m.id
                if !seenServerIds.contains(id) {
                    seenServerIds.insert(id)
                    deduped.append(m)
                } else if let client = m.clientMessageId, !client.isEmpty {
                    if !seenClientIds.contains(client) {
                        seenClientIds.insert(client)
                        deduped.append(m)
                    }
                } else {
                    // fallback (shouldn't be reached if id is non-optional)
                    deduped.append(m)
                }
            }
            self.messages = deduped

            // Trim & tombstone
            self.capInMemoryMessages(max: self.inMemoryMax)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .MessagesChanged, object: nil)
            }
        }
    }

    // MARK: - Trimming / tombstone

    func capInMemoryMessages(max: Int = 500) {
        guard max > 0 else { return }

        lock.async(flags: .barrier) {
            guard self.messages.count > max else { return }
            let toRemoveCount = self.messages.count - max
            let removedPrefix = Array(self.messages.prefix(toRemoveCount))

            // removedPrefix.first?.id works even if id is non-optional because .first returns Optional element
            if let oldestRemovedId = removedPrefix.first?.id {
                self.oldestRemovedMessageId = oldestRemovedId
            }

            self.messages.removeFirst(toRemoveCount)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .MessagesChanged, object: nil)
            }
        }
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
            if let idx = self.messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) {
                self.messages[idx] = serverDTO
                self.messages.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                    return $0.id < $1.id
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .MessagesChanged, object: nil)
                }
            } else {
                self.messages.append(serverDTO)
                self.messages.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                    return $0.id < $1.id
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .MessagesChanged, object: nil)
                }
            }
            self.setDeliveryState(clientMessageId: clientMessageId, state: .sent)
            self.capInMemoryMessages(max: self.inMemoryMax)
        }
    }
}
