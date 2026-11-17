import Foundation

/// UIKit uses this stable responder context to remember a keyboard the user
/// selected manually. It does not select or force an input language.
struct TypingConversationContext: Hashable {
    let userId: Int
    let kind: String
    let conversationId: Int

    var storageKey: String { "\(userId):\(kind):\(conversationId)" }

    var keyboardContextIdentifier: String {
        "chatforia.typing.\(storageKey)"
    }
}
