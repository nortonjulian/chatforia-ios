//
//  Environment.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import Foundation

enum Environment {
    // TODO: change to your real backend base URL
    static let apiBaseURL = URL(string: "http://localhost:5002")!

    static let requestTimeout: TimeInterval = 30
}
