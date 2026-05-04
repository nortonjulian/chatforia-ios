import Foundation

struct SMSMessageDTO: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let threadId: Int?
    let direction: String
    let fromNumber: String?
    let toNumber: String?
    let body: String?
    let provider: String?
    let providerMessageId: String?
    let media: [SMSMediaItemDTO]
    let createdAt: Date
    let editedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId
        case direction
        case fromNumber
        case toNumber
        case body
        case provider
        case providerMessageId
        case mediaUrls
        case createdAt
        case editedAt
    }

    init(
        id: Int,
        threadId: Int? = nil,
        direction: String,
        fromNumber: String? = nil,
        toNumber: String? = nil,
        body: String? = nil,
        provider: String? = nil,
        providerMessageId: String? = nil,
        media: [SMSMediaItemDTO] = [],
        createdAt: Date,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.direction = direction
        self.fromNumber = fromNumber
        self.toNumber = toNumber
        self.body = body
        self.provider = provider
        self.providerMessageId = providerMessageId
        self.media = media
        self.createdAt = createdAt
        self.editedAt = editedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(Int.self, forKey: .id)
        threadId = try c.decodeIfPresent(Int.self, forKey: .threadId)
        direction = try c.decodeIfPresent(String.self, forKey: .direction) ?? "in"
        fromNumber = try c.decodeIfPresent(String.self, forKey: .fromNumber)
        toNumber = try c.decodeIfPresent(String.self, forKey: .toNumber)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        providerMessageId = try c.decodeIfPresent(String.self, forKey: .providerMessageId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)

        if let items = try? c.decode([SMSMediaItemDTO].self, forKey: .mediaUrls) {
            media = items
        } else if let strings = try? c.decode([String].self, forKey: .mediaUrls) {
            media = strings.map { SMSMediaItemDTO(url: $0, contentType: nil) }
        } else if let dict = try? c.decode([String: String].self, forKey: .mediaUrls) {
            media = dict.values.map { SMSMediaItemDTO(url: $0, contentType: nil) }
        } else {
            media = []
        }
    }

    var isOutgoing: Bool {
        direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "out"
    }

    var trimmedBody: String? {
        body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var hasText: Bool {
        trimmedBody != nil
    }

    var hasMedia: Bool {
        !media.isEmpty
    }

    var mediaCount: Int {
        media.count
    }

    var displayFallbackText: String {
        if hasText { return trimmedBody ?? "" }
        if hasMedia {
            if media.contains(where: { $0.isImage }) { return "Photo" }
            if media.contains(where: { $0.isVideo }) { return "Video" }
            if media.contains(where: { $0.isAudio }) { return "Audio" }
            return "Attachment"
        }
        return ""
    }

    static func optimisticOutgoing(threadId: Int, to: String, body: String) -> SMSMessageDTO {
        SMSMessageDTO(
            id: -Int(Date().timeIntervalSince1970 * 1000),
            threadId: threadId,
            direction: "out",
            fromNumber: nil,
            toNumber: to,
            body: body,
            provider: nil,
            providerMessageId: nil,
            media: [],
            createdAt: Date(),
            editedAt: nil
        )
    }
}

struct SMSMediaItemDTO: Codable, Equatable, Sendable {
    let url: String
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case url
        case contentType
    }

    init(url: String, contentType: String? = nil) {
        self.url = url
        self.contentType = contentType
    }

    var normalizedContentType: String {
        contentType?.lowercased() ?? ""
    }

    var isImage: Bool {
        if normalizedContentType.hasPrefix("image/") { return true }
        let u = url.lowercased()
        return u.contains(".jpg") || u.contains(".jpeg") || u.contains(".png") || u.contains(".gif") || u.contains(".webp")
    }

    var isVideo: Bool {
        if normalizedContentType.hasPrefix("video/") { return true }
        let u = url.lowercased()
        return u.contains(".mp4") || u.contains(".mov") || u.contains(".webm")
    }

    var isAudio: Bool {
        if normalizedContentType.hasPrefix("audio/") { return true }
        let u = url.lowercased()
        return u.contains(".mp3") || u.contains(".m4a") || u.contains(".wav") || u.contains(".aac") || u.contains(".ogg")
    }

    var displayLabel: String {
        if isImage { return "Photo" }
        if isVideo { return "Video" }
        if isAudio { return "Audio" }
        return "Attachment"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
