//
//  ChatRoomDTO.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

//
//  AuthStore.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

struct ChatRoomDTO: Codable, Identifiable {
    let id: Int
    let name: String?
    let isGroup: Bool?
    let updatedAt: String?
    let lastMessage: MessagePreviewDTO?
    let participants: [UserPreviewDTO]?
}

struct UserPreviewDTO: Codable, Identifiable {
    let id: Int
    let username: String?
}

struct MessagePreviewDTO: Codable, Identifiable {
    let id: Int
    let content: String?
    let createdAt: String?
    let sender: UserPreviewDTO?
}

