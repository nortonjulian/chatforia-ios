//
//  Environment.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

enum Environment {
    static var apiBaseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:5002")!
        #elseif STAGING
        return URL(string: "https://staging-api.chatforia.com")!
        #else
        return URL(string: "https://api.chatforia.com")!
        #endif
    }
}

