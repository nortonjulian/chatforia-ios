//
//  ChatforiaApp.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

@main
struct ChatforiaApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .task {
                    await auth.bootstrap()
                }
        }
    }
}
