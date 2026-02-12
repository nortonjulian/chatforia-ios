//
//  TypingUpdateDTO.swift
//  Chatforia
//
//  Created by Julian Norton on 2/10/26.
//

import Foundation

struct TypingUpdateDTO: Decodable {
    let roomId: Int
    let userId: Int?
    let username: String?
    let isTyping: Bool
}

