import Foundation

/// Device-local typing preference; deliberately independent of app language and translation.
struct TypingConversationContext: Hashable {
    let userId: Int
    let kind: String
    let conversationId: Int

    var storageKey: String { "\(userId):\(kind):\(conversationId)" }

    func keyboardContextIdentifier(language: String?) -> String {
        // UIKit remembers the user's manually selected input mode for this responder context.
        // A language selection creates a separate memory context; it does not set the keyboard.
        "chatforia.typing.\(storageKey).\(language ?? "system")"
    }
}

struct TypingLanguagePreferences {
    private let defaults: UserDefaults
    private let key = "chatforia.typingLanguage.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func language(for context: TypingConversationContext?) -> String? {
        guard let context else { return nil }
        let stored = defaults.dictionary(forKey: key)?[context.storageKey] as? String
        return stored.flatMap { code in
            AppLanguages.all.contains(where: { $0.code == code }) ? code : nil
        }
    }

    func setLanguage(_ language: String?, for context: TypingConversationContext?) {
        guard let context else { return }
        guard language == nil || AppLanguages.all.contains(where: { $0.code == language }) else { return }
        var stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[context.storageKey] = language
        defaults.set(stored, forKey: key)
    }
}
