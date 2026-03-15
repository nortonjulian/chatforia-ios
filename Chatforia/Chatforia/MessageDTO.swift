import Foundation

// MARK: - MessagesEnvelope / Page
struct MessagesEnvelope: Codable {
    let items: [MessageDTO]
    let nextCursor: String?
    let nextCursorId: Int?
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor
        case nextCursorId
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = try container.decode([MessageDTO].self, forKey: .items)
        count = try? container.decode(Int.self, forKey: .count)
        nextCursorId = try? container.decode(Int.self, forKey: .nextCursorId)

        if let str = try? container.decode(String.self, forKey: .nextCursor) {
            nextCursor = str
        } else if let int = try? container.decode(Int.self, forKey: .nextCursor) {
            nextCursor = String(int)
        } else {
            nextCursor = nil
        }
    }
}

// MARK: - MessageDTO (server-authoritative shape)
struct MessageDTO: Codable, Identifiable, Equatable {
    let id: Int
    let contentCiphertext: String?
    let rawContent: String?

    let translations: [String: String]?
    let translatedFrom: String?

    let translatedForMe: String?
    let encryptedKeyForMe: String?

    let imageUrl: String?
    let audioUrl: String?
    let audioDurationSec: Double?

    let attachments: [AttachmentDTO]?

    let isExplicit: Bool?

    var createdAt: Date
    let expiresAt: Date?
    let editedAt: Date?

    let deletedBySender: Bool?
    let deletedForAll: Bool?
    let deletedAt: Date?
    let deletedById: Int?

    let sender: SenderDTO
    let readBy: [UserSummaryDTO]?

    let chatRoomId: Int?

    let reactionSummary: [String: Int]?
    let myReactions: [String]?

    let revision: Int?

    let clientMessageId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case contentCiphertext
        case rawContent
        case translations
        case translatedFrom
        case translatedForMe
        case encryptedKeyForMe
        case imageUrl
        case audioUrl
        case audioDurationSec
        case attachments
        case isExplicit
        case createdAt
        case expiresAt
        case editedAt
        case deletedBySender
        case deletedForAll
        case deletedAt
        case deletedById
        case sender
        case readBy
        case chatRoomId
        case reactionSummary
        case myReactions
        case revision
        case clientMessageId
    }

    init(
        id: Int,
        contentCiphertext: String? = nil,
        rawContent: String? = nil,
        translations: [String: String]? = nil,
        translatedFrom: String? = nil,
        translatedForMe: String? = nil,
        encryptedKeyForMe: String? = nil,
        imageUrl: String? = nil,
        audioUrl: String? = nil,
        audioDurationSec: Double? = nil,
        attachments: [AttachmentDTO]? = nil,
        isExplicit: Bool? = nil,
        createdAt: Date,
        expiresAt: Date? = nil,
        editedAt: Date? = nil,
        deletedBySender: Bool? = nil,
        deletedForAll: Bool? = nil,
        deletedAt: Date? = nil,
        deletedById: Int? = nil,
        sender: SenderDTO,
        readBy: [UserSummaryDTO]? = nil,
        chatRoomId: Int? = nil,
        reactionSummary: [String: Int]? = nil,
        myReactions: [String]? = nil,
        revision: Int? = nil,
        clientMessageId: String? = nil
    ) {
        self.id = id
        self.contentCiphertext = contentCiphertext
        self.rawContent = rawContent
        self.translations = translations
        self.translatedFrom = translatedFrom
        self.translatedForMe = translatedForMe
        self.encryptedKeyForMe = encryptedKeyForMe
        self.imageUrl = imageUrl
        self.audioUrl = audioUrl
        self.audioDurationSec = audioDurationSec
        self.attachments = attachments
        self.isExplicit = isExplicit
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.editedAt = editedAt
        self.deletedBySender = deletedBySender
        self.deletedForAll = deletedForAll
        self.deletedAt = deletedAt
        self.deletedById = deletedById
        self.sender = sender
        self.readBy = readBy
        self.chatRoomId = chatRoomId
        self.reactionSummary = reactionSummary
        self.myReactions = myReactions
        self.revision = revision
        self.clientMessageId = clientMessageId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(Int.self, forKey: .id)
        contentCiphertext = try c.decodeIfPresent(String.self, forKey: .contentCiphertext)
        rawContent = try c.decodeIfPresent(String.self, forKey: .rawContent)

        translations = try c.decodeIfPresent([String: String].self, forKey: .translations)
        translatedFrom = try c.decodeIfPresent(String.self, forKey: .translatedFrom)

        translatedForMe = try c.decodeIfPresent(String.self, forKey: .translatedForMe)
        encryptedKeyForMe = try c.decodeIfPresent(String.self, forKey: .encryptedKeyForMe)

        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        audioUrl = try c.decodeIfPresent(String.self, forKey: .audioUrl)

        if let dbl = try c.decodeIfPresent(Double.self, forKey: .audioDurationSec) {
            audioDurationSec = dbl
        } else if let intValue = try c.decodeIfPresent(Int.self, forKey: .audioDurationSec) {
            audioDurationSec = Double(intValue)
        } else {
            audioDurationSec = nil
        }

        attachments = try c.decodeIfPresent([AttachmentDTO].self, forKey: .attachments)

        isExplicit = try c.decodeIfPresent(Bool.self, forKey: .isExplicit)

        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)

        deletedBySender = try c.decodeIfPresent(Bool.self, forKey: .deletedBySender)
        deletedForAll = try c.decodeIfPresent(Bool.self, forKey: .deletedForAll)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        deletedById = try c.decodeIfPresent(Int.self, forKey: .deletedById)

        sender = try c.decode(SenderDTO.self, forKey: .sender)
        readBy = try c.decodeIfPresent([UserSummaryDTO].self, forKey: .readBy)

        chatRoomId = try c.decodeIfPresent(Int.self, forKey: .chatRoomId)

        reactionSummary = try c.decodeIfPresent([String: Int].self, forKey: .reactionSummary)
        myReactions = try c.decodeIfPresent([String].self, forKey: .myReactions)

        revision = try c.decodeIfPresent(Int.self, forKey: .revision)
        clientMessageId = try c.decodeIfPresent(String.self, forKey: .clientMessageId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(contentCiphertext, forKey: .contentCiphertext)
        try c.encodeIfPresent(rawContent, forKey: .rawContent)

        try c.encodeIfPresent(translations, forKey: .translations)
        try c.encodeIfPresent(translatedFrom, forKey: .translatedFrom)

        try c.encodeIfPresent(translatedForMe, forKey: .translatedForMe)
        try c.encodeIfPresent(encryptedKeyForMe, forKey: .encryptedKeyForMe)

        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(audioUrl, forKey: .audioUrl)
        try c.encodeIfPresent(audioDurationSec, forKey: .audioDurationSec)
        try c.encodeIfPresent(attachments, forKey: .attachments)

        try c.encodeIfPresent(isExplicit, forKey: .isExplicit)

        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try c.encodeIfPresent(editedAt, forKey: .editedAt)

        try c.encodeIfPresent(deletedBySender, forKey: .deletedBySender)
        try c.encodeIfPresent(deletedForAll, forKey: .deletedForAll)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(deletedById, forKey: .deletedById)

        try c.encode(sender, forKey: .sender)
        try c.encodeIfPresent(readBy, forKey: .readBy)

        try c.encodeIfPresent(chatRoomId, forKey: .chatRoomId)

        try c.encodeIfPresent(reactionSummary, forKey: .reactionSummary)
        try c.encodeIfPresent(myReactions, forKey: .myReactions)

        try c.encodeIfPresent(revision, forKey: .revision)
        try c.encodeIfPresent(clientMessageId, forKey: .clientMessageId)
    }

    static func == (lhs: MessageDTO, rhs: MessageDTO) -> Bool {
        lhs.id == rhs.id && lhs.clientMessageId == rhs.clientMessageId
    }

    static func optimistic(
        roomId: Int,
        clientMessageId: String,
        localId: Int,
        text: String,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?
    ) -> MessageDTO {
        let now = Date()
        return MessageDTO(
            id: localId,
            rawContent: text,
            attachments: nil,
            createdAt: now,
            sender: SenderDTO(
                id: senderId,
                username: senderUsername,
                publicKey: senderPublicKey,
                avatarUrl: nil
            ),
            chatRoomId: roomId,
            revision: 1,
            clientMessageId: clientMessageId
        )
    }
}

// MARK: - Sender / summaries
struct SenderDTO: Codable {
    let id: Int
    let username: String?
    let publicKey: String?
    let avatarUrl: String?
}

struct UserSummaryDTO: Codable {
    let id: Int
    let username: String?
    let avatarUrl: String?
}

// MARK: - Attachment
struct AttachmentDTO: Codable, Equatable {
    let id: Int?
    let kind: String?
    let url: String?
    let mimeType: String?
    let width: Int?
    let height: Int?
    let durationSec: Double?
    let caption: String?
    let thumbUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case url
        case mimeType
        case width
        case height
        case durationSec
        case caption
        case thumbUrl
    }

    init(
        id: Int? = nil,
        kind: String? = nil,
        url: String? = nil,
        mimeType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationSec: Double? = nil,
        caption: String? = nil,
        thumbUrl: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.durationSec = durationSec
        self.caption = caption
        self.thumbUrl = thumbUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decodeIfPresent(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)

        if let dbl = try c.decodeIfPresent(Double.self, forKey: .durationSec) {
            durationSec = dbl
        } else if let intValue = try c.decodeIfPresent(Int.self, forKey: .durationSec) {
            durationSec = Double(intValue)
        } else {
            durationSec = nil
        }

        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        thumbUrl = try c.decodeIfPresent(String.self, forKey: .thumbUrl)
    }
}
