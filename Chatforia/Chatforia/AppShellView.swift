//
//  AppShellView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct AppShellView: View {
    let user: UserDTO
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        TabView {
            ChatsRootView()
                .tabItem { Label("Chats", systemImage: "message") }

            ContactsRootView()
                .tabItem { Label("Contacts", systemImage: "person.2") }

            ProfileRootView(user: user)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}


