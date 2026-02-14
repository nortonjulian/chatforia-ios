//
//  MessageDTO.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

struct MessageSenderDTO: Codable {
    let id: Int
    let username: String?
    let publicKey: String?
    let avatarUrl: String?
}

struct MessageDTO: Codable, Identifiable {
    let id: Int
    let clientMessageId: String?

    let contentCiphertext: JSONValue?
    let rawContent: String?

    let translations: [String: String]?
    let translatedFrom: String?
    let translatedContent: String?
    let translatedTo: String?

    let translatedForMe: String?      // ✅ MUST be optional

    let isExplicit: Bool?
    let imageUrl: String?
    let audioUrl: String?
    let audioDurationSec: Double?
    let expiresAt: String?

    let deletedBySender: Bool?
    let deletedAt: String?
    let deletedForAll: Bool?
    let deletedById: Int?

    let senderId: Int?
    let sender: MessageSenderDTO?     // ✅ MUST be optional

    let chatRoomId: Int?
    let randomChatRoomId: Int?

    let createdAt: String?
    let isAutoReply: Bool?
}

extension MessageDTO {
    var effectiveSenderId: Int? {
        sender?.id ?? senderId
    }
}


