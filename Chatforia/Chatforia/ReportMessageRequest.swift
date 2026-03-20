import Foundation

struct ReportAttachmentPayload: Encodable {
    let id: Int?
    let kind: String?
    let url: String?
    let mimeType: String?
    let width: Int?
    let height: Int?
    let durationSec: Double?
    let caption: String?
    let thumbUrl: String?
}

struct ReportEvidenceMessage: Encodable {
    let messageId: Int
    let senderId: Int?
    let createdAt: String?
    let plaintext: String
    let translatedForMe: String?
    let rawContent: String?
    let content: String?
    let contentCiphertext: String?
    let encryptedKeyForMe: String?
    let attachments: [ReportAttachmentPayload]
    let deletedForAll: Bool
    let editedAt: String?
}

struct ReportClientMetadata: Encodable {
    let platform: String
    let locale: String
}

struct ReportMessageRequest: Encodable {
    let messageId: Int
    let chatRoomId: Int
    let reportedUserId: Int?
    let reason: String
    let details: String
    let blockAfterReport: Bool
    let messages: [ReportEvidenceMessage]
    let clientMetadata: ReportClientMetadata
}
