import XCTest
import SwiftUI
@testable import Chatforia

@MainActor
final class TypingLanguagePreferencesTests: XCTestCase {
    func testNativeKeyboardContextIsIsolatedByConversationAndAccount() {
        let chat = TypingConversationContext(userId: 1, kind: "chat", conversationId: 42)
        let otherChat = TypingConversationContext(userId: 1, kind: "chat", conversationId: 43)
        let otherUser = TypingConversationContext(userId: 2, kind: "chat", conversationId: 42)
        let sms = TypingConversationContext(userId: 1, kind: "sms", conversationId: 42)

        XCTAssertEqual(chat.keyboardContextIdentifier, "chatforia.typing.1:chat:42")
        XCTAssertNotEqual(chat.keyboardContextIdentifier, otherChat.keyboardContextIdentifier)
        XCTAssertNotEqual(chat.keyboardContextIdentifier, otherUser.keyboardContextIdentifier)
        XCTAssertNotEqual(chat.keyboardContextIdentifier, sms.keyboardContextIdentifier)
    }

    func testNativeContextDoesNotChangeAppOrTranslationPreferences() {
        let defaults = UserDefaults.standard
        let language = defaults.string(forKey: "chatforia_language")
        let translation = defaults.object(forKey: "autoTranslate")
        defer {
            defaults.set(language, forKey: "chatforia_language")
            defaults.set(translation, forKey: "autoTranslate")
        }
        defaults.set("fr", forKey: "chatforia_language")
        defaults.set(true, forKey: "autoTranslate")

        _ = TypingConversationContext(userId: 7, kind: "chat", conversationId: 8)
            .keyboardContextIdentifier

        XCTAssertEqual(defaults.string(forKey: "chatforia_language"), "fr")
        XCTAssertTrue(defaults.bool(forKey: "autoTranslate"))
    }

    func testChangingConversationContextLeavesComposerTextIntact() {
        let first = TypingConversationContext(userId: 1, kind: "chat", conversationId: 10)
        let second = TypingConversationContext(userId: 1, kind: "chat", conversationId: 11)
        let view = ConversationTextView()
        view.text = "draft with 日本語"
        view.keyboardContextIdentifier = first.keyboardContextIdentifier
        XCTAssertEqual(view.textInputContextIdentifier, first.keyboardContextIdentifier)
        view.keyboardContextIdentifier = second.keyboardContextIdentifier
        XCTAssertEqual(view.text, "draft with 日本語")
        XCTAssertEqual(view.textInputContextIdentifier, second.keyboardContextIdentifier)
    }

    func testComposerDelegateKeepsDraftAndFocusBindings() {
        final class State { var draft = ""; var focused = false }
        let state = State()
        let composer = ContextualMessageTextView(
            text: Binding(get: { state.draft }, set: { state.draft = $0 }),
            isFocused: Binding(get: { state.focused }, set: { state.focused = $0 }),
            contextIdentifier: "chatforia.typing.1:chat:1",
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
