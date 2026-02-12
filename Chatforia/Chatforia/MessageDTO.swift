//
//  MessageDTO.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

struct MessageDTO: Codable, Identifiable {
    let id: Int

    // ✅ Needed for optimistic reconciliation + socket de-dupe
    // Backend should echo this back (even before you persist it in DB).
    let clientMessageId: String?

    // Core content fields (matching backend)
    let contentCiphertext: String?
    let rawContent: String?
    let translations: [String: String]?
    let translatedFrom: String?
    let translatedContent: String?
    let translatedTo: String?

    // Moderation / media / lifecycle
    let isExplicit: Bool?
    let imageUrl: String?
    let audioUrl: String?
    let audioDurationSec: Double?
    let expiresAt: String?

    // Deletion flags
    let deletedBySender: Bool?
    let deletedAt: String?
    let deletedForAll: Bool?
    let deletedById: Int?

    // Routing
    let senderId: Int?
    let chatRoomId: Int?
    let randomChatRoomId: Int?

    // Timestamps / meta
    let createdAt: String?
    let isAutoReply: Bool?
}




