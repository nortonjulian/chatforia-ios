import Foundation
import SwiftUI
import Combine

@MainActor
final class DecryptedMessageTextStore: ObservableObject {
    static let shared = DecryptedMessageTextStore()

    @Published private(set) var values: [Int: String] = [:]

    private init() {}

    func text(for messageId: Int) -> String? {
        values[messageId]
    }

    func setText(_ text: String, for messageId: Int) {
        values[messageId] = text

        NotificationCenter.default.post(
            name: .MessagesChanged,
            object: nil
        )
    }

    func removeText(for messageId: Int) {
        values.removeValue(forKey: messageId)
    }

    // Duplicate edited events and receipt updates must not evict valid text.
    // Only a new message version, changed encryption bundle, or deletion does.
    func invalidateTextIfNeeded(for incoming: MessageDTO, current: MessageDTO?) {
        guard incoming.id > 0 else { return }

        if incoming.deletedForAll == true || incoming.deletedBySender == true {
            removeText(for: incoming.id)
            return
        }

        guard let current else {
            if incoming.editedAt != nil { removeText(for: incoming.id) }
            return
        }

        let newerRevision = (incoming.revision ?? 0) > (current.revision ?? 0)
        let newerEdit = incoming.editedAt.map {
            $0 > (current.editedAt ?? .distantPast)
        } ?? false
        let changedPayload = incoming.encryptedPayloadForMe.map {
            $0 != current.encryptedPayloadForMe
        } ?? false
        let changedLegacyBundle: Bool
        if let ciphertext = incoming.contentCiphertext,
           let key = incoming.encryptedKeyForMe {
            changedLegacyBundle = ciphertext != current.contentCiphertext ||
                key != current.encryptedKeyForMe
        } else {
            // Partial metadata must not be treated as a new encryption bundle.
            changedLegacyBundle = false
        }

        if newerRevision || newerEdit || changedPayload || changedLegacyBundle {
            removeText(for: incoming.id)
        }
    }

    func replaceTextIfPresent(_ text: String, for messageId: Int) {
        guard values[messageId] != nil else { return }

        values[messageId] = text

        NotificationCenter.default.post(
            name: .MessagesChanged,
            object: nil
        )
    }

    func moveText(from oldMessageId: Int, to newMessageId: Int) {
        guard oldMessageId != newMessageId else { return }
        guard let text = values[oldMessageId] else { return }

        values[newMessageId] = text
        values.removeValue(forKey: oldMessageId)

        NotificationCenter.default.post(
            name: .MessagesChanged,
            object: nil
        )
    }

    func clearAll() {
        values.removeAll()

        NotificationCenter.default.post(
            name: .MessagesChanged,
            object: nil
        )
    }
}
