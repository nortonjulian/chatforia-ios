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
        "chatforia.typing.\(storageKey).\(TypingLanguagePreferences.canonicalCode(language) ?? "system")"
    }
}

struct TypingLanguagePreferences {
    private let defaults: UserDefaults
    private let key = "chatforia.typingLanguage.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func canonicalCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return AppLanguages.all.first { $0.code.lowercased() == normalized.lowercased() }?.code
    }

    static func localizedName(for option: LanguageOption, appLanguage: String) -> String {
        // The catalog calls Kurmanji "ku"; the iOS menu stores the more precise kmr tag.
        let catalogCode = option.code == "kmr" ? "ku" : option.code
        let key = "languages.\(catalogCode)"
        let translated = appText(key, languageCode: appLanguage)
        if translated != key { return translated }

        // A few menu variants (including pt-BR) have no exact catalog key.
        // Ask the locale for the exact identifier before falling back to the menu name.
        let locale = Locale(identifier: appLanguage)
        return locale.localizedString(forIdentifier: option.code) ?? option.name
    }

    func language(for context: TypingConversationContext?) -> String? {
        guard let context else { return nil }
        let stored = defaults.dictionary(forKey: key)?[context.storageKey] as? String
        return Self.canonicalCode(stored)
    }

    func setLanguage(_ language: String?, for context: TypingConversationContext?) {
        guard let context else { return }
        guard language == nil || Self.canonicalCode(language) != nil else { return }
        var stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[context.storageKey] = Self.canonicalCode(language)
        defaults.set(stored, forKey: key)
    }
}
