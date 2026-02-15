//
//  Environment.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

enum AppEnvironment {

    static var apiBaseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:5002")!
        #elseif STAGING
        return URL(string: "https://staging-api.chatforia.com")!
        #else
        return URL(string: "https://api.chatforia.com")!
        #endif
    }

    static var requestTimeout: TimeInterval {
        #if DEBUG
        return 60   // longer for local debugging
        #else
        return 30   // production safe default
        #endif
    }
}


