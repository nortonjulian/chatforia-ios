import XCTest
@testable import Chatforia

@MainActor
final class SMSPreviewTranslationTests: XCTestCase {
    private func conversation(text: String, hasMedia: Bool = false) -> ConversationDTO {
        ConversationDTO(kind: "sms", id: 67, title: "Saved contact", displayName: nil,
                        updatedAt: nil, isGroup: false, phone: "+13035550123",
                        unreadCount: 1, avatarUsers: nil,
                        last: ConversationLastDTO(text: text, messageId: 501, at: nil,
                                                  hasMedia: hasMedia, mediaCount: nil,
                                                  mediaKinds: nil, thumbUrl: nil, senderName: nil))
    }

    func testSpanishChatsPreviewUsesTranslationAndCanShowOriginal() {
        let message = SMSPreviewTranslation.message(for: conversation(text: "Hello"))
        XCTAssertEqual(message?.id, 501)
        XCTAssertEqual(message?.body, "Hello")
        XCTAssertEqual(SMSPreviewTranslation.subtitle(original: "Hello",
            presentation: .translated("Hola"), showOriginal: false,
            originalBody: message?.trimmedBody), "Hola")
        XCTAssertEqual(SMSPreviewTranslation.subtitle(original: "Hello",
            presentation: .translated("Hola"), showOriginal: true,
            originalBody: message?.trimmedBody), "Hola · Hello")
    }

    func testPreviewShowsPendingWithoutEnglishFlashThenOriginalOnFailure() {
        XCTAssertEqual(SMSPreviewTranslation.subtitle(original: "Hello",
            presentation: .pending, showOriginal: false, originalBody: "Hello"), "…")
        XCTAssertEqual(SMSPreviewTranslation.subtitle(original: "Hello",
            presentation: .original, showOriginal: false, originalBody: "Hello"), "Hello")
        XCTAssertNil(SMSPreviewTranslation.message(for: conversation(text: "Photo", hasMedia: true)))
    }
}
