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

// Example — adjust to match your actual MessageDTO file
struct MessageDTO: Codable {
    var id: Int
    var clientMessageId: String?
    var contentCiphertext: String?
    var rawContent: String?
    var translations: String?            // or whatever type
    var translatedFrom: String?
    var translatedContent: String?
    var translatedTo: String?
    var translatedForMe: String?
    var isExplicit: Bool?
    var imageUrl: String?
    var audioUrl: String?
    var audioDurationSec: Int?
    var expiresAt: String?
    var deletedBySender: Bool?
    var deletedAt: String?
    var deletedForAll: Bool?
    var deletedById: Int?
    var senderId: Int?
    var sender: UserDTO?                 // example
    var chatRoomId: Int
    var randomChatRoomId: Int?
    var createdAt: String?               // made var above
    var isAutoReply: Bool?
    // Add revision as optional so old rows decode and optimistic ones can set it.
    var revision: Int?
    
    // CodingKeys / init if you already have them — just ensure createdAt and revision map correctly.
}

extension MessageDTO {
    var effectiveSenderId: Int? {
        sender?.id ?? senderId
    }
}


