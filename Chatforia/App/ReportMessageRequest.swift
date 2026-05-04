import Foundation

struct ReportMessageRequest: Encodable {
    let messageId: Int
    let reason: String
    let details: String?
    let contextCount: Int
    let blockAfterReport: Bool
}

struct ReportMessageResponse: Decodable {
    let success: Bool
    let report: ReportSummary
}

struct ReportSummary: Decodable {
    let id: Int
    let messageId: Int
    let reporterId: Int
    let reportedUserId: Int?
    let chatRoomId: Int?
    let decryptedContent: String?
    let reason: String?
    let details: String?
    let blockApplied: Bool
    let status: String
    let createdAt: String
}
