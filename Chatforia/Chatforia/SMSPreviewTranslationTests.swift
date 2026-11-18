import XCTest
@testable import Chatforia

@MainActor
final class SMSPreviewTranslationTests: XCTestCase {
    private func conversation(text: String, hasMedia: Bool = false,
                              direction: String? = "in") -> ConversationDTO {
        ConversationDTO(kind: "sms", id: 67, title: "Saved contact", displayName: nil,
                        updatedAt: nil, isGroup: false, phone: "+13035550123",
                        unreadCount: 1, avatarUsers: nil,
                        last: ConversationLastDTO(text: text, messageId: 501, at: nil,
                                                  hasMedia: hasMedia, mediaCount: nil,
                                                  mediaKinds: nil, thumbUrl: nil, senderName: nil,
                                                  direction: direction))
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

    func testOutgoingPreviewNeverWaitsForTranslation() {
        let outgoing = conversation(text: "Sent", direction: "out")
        XCTAssertNil(SMSPreviewTranslation.message(for: outgoing))
        XCTAssertEqual(SMSPreviewTranslation.subtitle(original: "Sent",
            presentation: .original, showOriginal: false, originalBody: nil), "Sent")

        // A server without the new field keeps the previous incoming behavior.
        XCTAssertNotNil(SMSPreviewTranslation.message(for:
            conversation(text: "Received", direction: nil)))
    }

    func testRestrictedMixedMmsCaptionStillRequestsTranslationButMediaLabelDoesNot() {
        let caption = ConversationDTO(kind: "sms", id: 67, title: "Saved contact", displayName: nil,
            updatedAt: nil, isGroup: false, phone: "+13035550123", unreadCount: 1, avatarUsers: nil,
            last: ConversationLastDTO(text: "Keep this caption", messageId: 501, at: nil,
                hasMedia: true, mediaCount: 1, mediaKinds: ["audio"], thumbUrl: nil,
                senderName: nil, direction: "in", mediaRestricted: true))
        XCTAssertEqual(SMSPreviewTranslation.message(for: caption)?.body, "Keep this caption")

        let label = ConversationDTO(kind: "sms", id: 67, title: "Saved contact", displayName: nil,
            updatedAt: nil, isGroup: false, phone: "+13035550123", unreadCount: 1, avatarUsers: nil,
            last: ConversationLastDTO(text: "Voice note", messageId: 502, at: nil,
                hasMedia: true, mediaCount: 1, mediaKinds: ["audio"], thumbUrl: nil,
                senderName: nil, direction: "in", mediaRestricted: true))
        XCTAssertNil(SMSPreviewTranslation.message(for: label))
        let legacyLabel = ConversationDTO(kind: "sms", id: 67, title: "Saved contact", displayName: nil,
            updatedAt: nil, isGroup: false, phone: "+13035550123", unreadCount: 1, avatarUsers: nil,
            last: ConversationLastDTO(text: "[audio]", messageId: 503, at: nil,
                hasMedia: true, mediaCount: 1, mediaKinds: ["audio"], thumbUrl: nil,
                senderName: nil, direction: "in", mediaRestricted: true))
        XCTAssertNil(SMSPreviewTranslation.message(for: legacyLabel))
    }

    func testDirectionDecodesFromConversationPayload() throws {
        let json = #"{"text":"Sent","messageId":501,"direction":"out"}"#.data(using: .utf8)!
        let last = try JSONDecoder().decode(ConversationLastDTO.self, from: json)
        XCTAssertEqual(last.direction, "out")
    }
}
