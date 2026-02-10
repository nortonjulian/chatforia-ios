//
//  ProfileRootView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct ProfileRootView: View {
    let user: UserDTO
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Username", value: user.username)
                    LabeledContent("Email", value: user.email)
                    if let plan = user.plan { LabeledContent("Plan", value: plan) }
                    if let role = user.role { LabeledContent("Role", value: role) }
                }

                Section("Preferences") {
                    if let lang = user.preferredLanguage {
                        LabeledContent("Language", value: lang)
                    } else {
                        LabeledContent("Language", value: "—")
                    }

                    if let theme = user.theme {
                        LabeledContent("Theme", value: theme)
                    } else {
                        LabeledContent("Theme", value: "—")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Text("Log out")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

