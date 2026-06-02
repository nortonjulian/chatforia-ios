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