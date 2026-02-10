//
//  UserDTO.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

struct UserDTO: Codable, Identifiable {
    let id: Int
    let email: String
    let username: String
    let publicKey: String?
    let plan: String?
    let role: String?
    let preferredLanguage: String?
    let theme: String?
}

