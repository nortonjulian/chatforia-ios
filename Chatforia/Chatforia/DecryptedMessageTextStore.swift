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
    }
}
