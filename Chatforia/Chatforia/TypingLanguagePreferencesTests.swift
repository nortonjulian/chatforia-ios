import XCTest
import SwiftUI
@testable import Chatforia

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
        let preferences = TypingLanguagePreferences(defaults: defaults)
        let chat = TypingConversationContext(userId: 7, kind: "chat", conversationId: 8)
        preferences.setLanguage("ja", for: chat)
        XCTAssertEqual(defaults.string(forKey: "chatforia_language"), "fr")
        XCTAssertTrue(defaults.bool(forKey: "autoTranslate"))
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
}
