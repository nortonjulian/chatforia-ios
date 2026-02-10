//
//  ContactsRootView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct ContactsRootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Contacts")
                    .font(.title2).bold()

                Text("Next: wire saved contacts + start chat.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Contacts")
        }
    }
}

