import XCTest
import SwiftUI
@testable import Chatforia

@MainActor
final class TypingLanguagePreferencesTests: XCTestCase {
    func testConversationAndAccountIsolationAndManualSystemOverride() {
        let suite = "TypingLanguagePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = TypingLanguagePreferences(defaults: defaults)
        let chat = TypingConversationContext(userId: 1, kind: "chat", conversationId: 42)
        let otherChat = TypingConversationContext(userId: 1, kind: "chat", conversationId: 43)
        let otherUser = TypingConversationContext(userId: 2, kind: "chat", conversationId: 42)
        let sms = TypingConversationContext(userId: 1, kind: "sms", conversationId: 42)

        preferences.setLanguage("es", for: chat)
        preferences.setLanguage("ja", for: otherChat)
        XCTAssertEqual(preferences.language(for: chat), "es")
        XCTAssertEqual(preferences.language(for: otherChat), "ja")
        XCTAssertNil(preferences.language(for: otherUser))
        XCTAssertNil(preferences.language(for: sms))
        XCTAssertNotEqual(chat.keyboardContextIdentifier(language: "es"),
                          otherChat.keyboardContextIdentifier(language: "es"))

        preferences.setLanguage(nil, for: chat)
        XCTAssertNil(preferences.language(for: chat))
        XCTAssertEqual(preferences.language(for: otherChat), "ja")
        XCTAssertNil(preferences.language(for: nil))
    }

    func testKeyboardContextDoesNotChangeAppOrTranslationPreferences() {
        let suite = "TypingLanguagePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("fr", forKey: "chatforia_language")
        defaults.set(true, forKey: "autoTranslate")
        let profile = SettingsViewModel()
        profile.preferredLanguage = "fr"
        profile.autoTranslate = true
        profile.showOriginalWithTranslation = true
        let preferences = TypingLanguagePreferences(defaults: defaults)
        let chat = TypingConversationContext(userId: 7, kind: "chat", conversationId: 8)
        preferences.setLanguage("ja", for: chat)
        XCTAssertEqual(defaults.string(forKey: "chatforia_language"), "fr")
        XCTAssertTrue(defaults.bool(forKey: "autoTranslate"))
        XCTAssertEqual(profile.preferredLanguage, "fr")
        XCTAssertTrue(profile.autoTranslate)
        XCTAssertTrue(profile.showOriginalWithTranslation)
        XCTAssertEqual(preferences.language(for: chat), "ja")
        XCTAssertNotEqual(chat.keyboardContextIdentifier(language: "ja"),
                          chat.keyboardContextIdentifier(language: nil))
        preferences.setLanguage("not a language", for: chat)
        XCTAssertEqual(preferences.language(for: chat), "ja")
    }

    func testChangingConversationContextLeavesComposerTextIntact() {
        let first = TypingConversationContext(userId: 1, kind: "chat", conversationId: 10)
        let second = TypingConversationContext(userId: 1, kind: "chat", conversationId: 11)
        let view = ConversationTextView()
        view.text = "draft with 日本語"
        view.keyboardContextIdentifier = first.keyboardContextIdentifier(language: "ja")
        XCTAssertEqual(view.textInputContextIdentifier, view.keyboardContextIdentifier)
        view.keyboardContextIdentifier = second.keyboardContextIdentifier(language: "es")
        XCTAssertEqual(view.text, "draft with 日本語")
        XCTAssertNotEqual(view.textInputContextIdentifier,
                          first.keyboardContextIdentifier(language: "ja"))
    }

    func testComposerDelegateKeepsDraftAndFocusBindings() {
        final class State { var draft = ""; var focused = false }
        let state = State()
        let composer = ContextualMessageTextView(
            text: Binding(get: { state.draft }, set: { state.draft = $0 }),
            isFocused: Binding(get: { state.focused }, set: { state.focused = $0 }),
            contextIdentifier: "chatforia.typing.1:chat:1.system",
            placeholder: "Message",
            textColor: .label,
            isEnabled: true
        )
        let delegate = composer.makeCoordinator()
        let field = ConversationTextView()
        field.text = "Hola 日本語"
        delegate.textViewDidBeginEditing(field)
        delegate.textViewDidChange(field)
        XCTAssertTrue(state.focused)
        XCTAssertEqual(state.draft, "Hola 日本語")
        delegate.textViewDidEndEditing(field)
        XCTAssertFalse(state.focused)
    }

    func testEverySupportedChoiceHasAStableDistinctKeyboardContext() {
        let suite = "TypingLanguagePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = TypingLanguagePreferences(defaults: defaults)
        let conversation = TypingConversationContext(userId: 9, kind: "chat", conversationId: 10)
        XCTAssertEqual(AppLanguages.all.count, 147)
        var identifiers = Set<String>()
        for option in AppLanguages.all {
            preferences.setLanguage(option.code, for: conversation)
            XCTAssertEqual(preferences.language(for: conversation), option.code)
            identifiers.insert(conversation.keyboardContextIdentifier(language: option.code))
            XCTAssertFalse(TypingLanguagePreferences.localizedName(for: option, appLanguage: "es").isEmpty)
        }
        XCTAssertEqual(identifiers.count, AppLanguages.all.count)
    }

    func testScriptsRegionsAndUnsupportedLanguageFallback() {
        let representative = [
            "es", "pt-BR", "ru", "sr", "ar", "prs", "ur", "hi", "mr", "ne",
            "zh-Hans", "zh-Hant", "ja", "ko", "yue", "mni-Mtei", "am", "he",
            "th", "bo", "kmr", "nb"
        ]
        for code in representative {
            XCTAssertEqual(TypingLanguagePreferences.canonicalCode(code), code)
        }
        XCTAssertEqual(TypingLanguagePreferences.canonicalCode("ZH_hant"), "zh-Hant")
        XCTAssertEqual(TypingLanguagePreferences.canonicalCode("PT_br"), "pt-BR")
        XCTAssertEqual(TypingLanguagePreferences.canonicalCode("MNI_mtei"), "mni-Mtei")
        XCTAssertNil(TypingLanguagePreferences.canonicalCode("zz"))
        XCTAssertNil(TypingLanguagePreferences.canonicalCode("pt"))

        let chat = TypingConversationContext(userId: 1, kind: "chat", conversationId: 1)
        XCTAssertTrue(chat.keyboardContextIdentifier(language: "ZH_hant").hasSuffix("zh-Hant"))
        XCTAssertTrue(chat.keyboardContextIdentifier(language: "zz").hasSuffix("system"))
        XCTAssertNotEqual(chat.keyboardContextIdentifier(language: "zh-Hans"),
                          chat.keyboardContextIdentifier(language: "zh-Hant"))
    }

    func testKeyboardMenuUsesAppLocalizationWithoutCollapsingPortugueseRegion() {
        let portuguese = AppLanguages.all.first { $0.code == "pt-BR" }!
        let kurmanji = AppLanguages.all.first { $0.code == "kmr" }!
        let brazilianName = TypingLanguagePreferences.localizedName(for: portuguese, appLanguage: "es")
        XCTAssertTrue(brazilianName.localizedCaseInsensitiveContains("Brasil"))
        XCTAssertNotEqual(brazilianName, "Portuguese (Brazil)")
        XCTAssertEqual(TypingLanguagePreferences.localizedName(for: kurmanji, appLanguage: "es"),
                       appText("languages.ku", languageCode: "es"))
        XCTAssertEqual(appText("keyboard.system", languageCode: "es"), "Teclado del sistema")
        XCTAssertTrue(appText("keyboard.help", languageCode: "fr").contains("clavier"))
        XCTAssertNotEqual(appText("keyboard.typingLanguage", languageCode: "pt-BR"), "Typing language")
        XCTAssertEqual(TypingLanguagePreferences.canonicalCode("pt-BR"), "pt-BR")
        XCTAssertNil(TypingLanguagePreferences.canonicalCode("pt"))
    }

    func testKeyboardCopyIsLocalizedForEverySupportedAppLanguage() {
        let sources = [
            "keyboard.help": "Choose a language, then use the keyboard language key to switch. iOS may remember it for this conversation.",
            "keyboard.system": "System keyboard",
            "keyboard.typingLanguage": "Typing language"
        ]
        for option in AppLanguages.all where option.code != "en" {
            for (key, english) in sources {
                let localized = appText(key, languageCode: option.code)
                XCTAssertNotEqual(localized.caseInsensitiveCompare(english), .orderedSame,
                    "\(key) fell back to English for \(option.code)")
                XCTAssertNotEqual(localized, key, "\(key) is missing for \(option.code)")
            }
        }
    }
}
