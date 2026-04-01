import Foundation

extension MessageDTO {
    static func merged(current: MessageDTO, incoming: MessageDTO) -> MessageDTO {
        MessageDTO(
            id: incoming.id,
            contentCiphertext: (incoming.deletedForAll == true)
                ? nil
                : (incoming.contentCiphertext ?? current.contentCiphertext),
            rawContent: {
                if incoming.deletedForAll == true {
                    return nil
                }
                if incoming.editedAt != nil {
                    return incoming.rawContent
                }
                return incoming.rawContent ?? current.rawContent
            }(),
            translations: incoming.translations ?? current.translations,
            translatedFrom: incoming.translatedFrom ?? current.translatedFrom,
            translatedForMe: incoming.translatedForMe ?? current.translatedForMe,
            encryptedKeyForMe: incoming.encryptedKeyForMe ?? current.encryptedKeyForMe,
            imageUrl: incoming.imageUrl ?? current.imageUrl,
            audioUrl: incoming.audioUrl ?? current.audioUrl,
            audioDurationSec: incoming.audioDurationSec ?? current.audioDurationSec,
            attachments: preferredAttachments(current: current.attachments, incoming: incoming.attachments),
            isExplicit: incoming.isExplicit ?? current.isExplicit,
            createdAt: incoming.createdAt,
            expiresAt: incoming.expiresAt ?? current.expiresAt,
            editedAt: incoming.editedAt ?? current.editedAt,
            deletedBySender: incoming.deletedBySender ?? current.deletedBySender,
            deletedForAll: incoming.deletedForAll ?? current.deletedForAll,
            deletedAt: incoming.deletedAt ?? current.deletedAt,
            deletedById: incoming.deletedById ?? current.deletedById,
            sender: preferredSender(current: current.sender, incoming: incoming.sender),
            readBy: preferredReadBy(current: current.readBy, incoming: incoming.readBy),
            chatRoomId: incoming.chatRoomId ?? current.chatRoomId,
            reactionSummary: preferredReactionSummary(current: current.reactionSummary, incoming: incoming.reactionSummary),
            myReactions: preferredMyReactions(current: current.myReactions, incoming: incoming.myReactions),
            revision: max(incoming.revision ?? 0, current.revision ?? 0) == 0
                ? (incoming.revision ?? current.revision)
                : max(incoming.revision ?? 0, current.revision ?? 0),
            clientMessageId: incoming.clientMessageId ?? current.clientMessageId
        )
    }

    private static func preferredAttachments(
        current: [AttachmentDTO]?,
        incoming: [AttachmentDTO]?
    ) -> [AttachmentDTO]? {
        guard let incoming, !incoming.isEmpty else { return current }
        guard let current, !current.isEmpty else { return incoming }

        let merged = zipLongest(current, incoming).compactMap { currentAtt, incomingAtt -> AttachmentDTO? in
            switch (currentAtt, incomingAtt) {
            case let (nil, rhs):
                return rhs
            case let (lhs, nil):
                return lhs
            case let (lhs?, rhs?):
                return AttachmentDTO(
                    id: rhs.id ?? lhs.id,
                    kind: rhs.kind ?? lhs.kind,
                    url: rhs.url ?? lhs.url,
                    mimeType: rhs.mimeType ?? lhs.mimeType,
                    width: rhs.width ?? lhs.width,
                    height: rhs.height ?? lhs.height,
                    durationSec: rhs.durationSec ?? lhs.durationSec,
                    caption: (rhs.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? rhs.caption
                        : lhs.caption,
                    thumbUrl: rhs.thumbUrl ?? lhs.thumbUrl
                )
            }
        }

        return merged.isEmpty ? incoming : merged
    }

    private static func zipLongest<T>(_ lhs: [T], _ rhs: [T]) -> [(T?, T?)] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            let left = index < lhs.count ? lhs[index] : nil
            let right = index < rhs.count ? rhs[index] : nil
            return (left, right)
        }
    }

    private static func preferredReadBy(
        current: [UserSummaryDTO]?,
        incoming: [UserSummaryDTO]?
    ) -> [UserSummaryDTO]? {
        if let incoming, !incoming.isEmpty { return incoming }
        return current
    }

    private static func preferredReactionSummary(
        current: [String: Int]?,
        incoming: [String: Int]?
    ) -> [String: Int]? {
        if let incoming, !incoming.isEmpty { return incoming }
        return current
    }

    private static func preferredMyReactions(
        current: [String]?,
        incoming: [String]?
    ) -> [String]? {
        if let incoming, !incoming.isEmpty { return incoming }
        return current
    }

    private static func preferredSender(
        current: SenderDTO,
        incoming: SenderDTO
    ) -> SenderDTO {
        let incomingScore =
            (incoming.username?.isEmpty == false ? 1 : 0) +
            (incoming.publicKey?.isEmpty == false ? 1 : 0) +
            (incoming.avatarUrl?.isEmpty == false ? 1 : 0)

        let currentScore =
            (current.username?.isEmpty == false ? 1 : 0) +
            (current.publicKey?.isEmpty == false ? 1 : 0) +
            (current.avatarUrl?.isEmpty == false ? 1 : 0)

        return incomingScore >= currentScore ? incoming : current
    }
    
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func decodeFlexibleDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let str = try? container.decode(String.self, forKey: key) {
            if let d = iso8601Fractional.date(from: str) ?? iso8601Plain.date(from: str) {
                return d
            }
        }

        if let seconds = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let millis = try? container.decode(Int64.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        }

        return nil
    }

    private static func decodeFlexibleDateIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        guard container.contains(key) else { return nil }
        return try decodeFlexibleDate(from: container, forKey: key)
    }
}

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

    init(
        items: [MessageDTO],
        nextCursor: String? = nil,
        nextCursorId: Int? = nil,
        count: Int? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.nextCursorId = nextCursorId
        self.count = count
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

        createdAt = try Self.decodeFlexibleDate(from: c, forKey: .createdAt) ?? Date()
        expiresAt = try Self.decodeFlexibleDateIfPresent(from: c, forKey: .expiresAt)
        editedAt = try Self.decodeFlexibleDateIfPresent(from: c, forKey: .editedAt)
        deletedAt = try Self.decodeFlexibleDateIfPresent(from: c, forKey: .deletedAt)

        deletedBySender = try c.decodeIfPresent(Bool.self, forKey: .deletedBySender)
        deletedForAll = try c.decodeIfPresent(Bool.self, forKey: .deletedForAll)
        
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
        lhs.id == rhs.id &&
        lhs.clientMessageId == rhs.clientMessageId &&
        lhs.revision == rhs.revision &&
        lhs.editedAt == rhs.editedAt &&
        lhs.rawContent == rhs.rawContent &&
        lhs.translatedForMe == rhs.translatedForMe &&
        lhs.deletedForAll == rhs.deletedForAll &&
        lhs.deletedBySender == rhs.deletedBySender &&
        lhs.reactionSummary == rhs.reactionSummary &&
        lhs.myReactions == rhs.myReactions &&
        lhs.readBy?.count == rhs.readBy?.count
    }

    static func optimistic(
        roomId: Int,
        clientMessageId: String,
        localId: Int,
        text: String? = nil,
        attachments: [AttachmentDTO]? = nil,
        imageUrl: String? = nil,
        audioUrl: String? = nil,
        audioDurationSec: Double? = nil,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?
    ) -> MessageDTO {
        let now = Date()
        return MessageDTO(
            id: localId,
            rawContent: text,
            imageUrl: imageUrl,
            audioUrl: audioUrl,
            audioDurationSec: audioDurationSec,
            attachments: attachments,
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

    static func optimisticImage(
        roomId: Int,
        clientMessageId: String,
        localId: Int,
        imageURL: String,
        senderId: Int,
        senderUsername: String?,
        senderPublicKey: String?,
        caption: String? = nil
    ) -> MessageDTO {
        let attachment = AttachmentDTO(
            id: nil,
            kind: "IMAGE",
            url: imageURL,
            mimeType: "image/jpeg",
            width: nil,
            height: nil,
            durationSec: nil,
            caption: caption,
            thumbUrl: imageURL
        )

        return optimistic(
            roomId: roomId,
            clientMessageId: clientMessageId,
            localId: localId,
            text: caption,
            attachments: [attachment],
            imageUrl: imageURL,
            senderId: senderId,
            senderUsername: senderUsername,
            senderPublicKey: senderPublicKey
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
