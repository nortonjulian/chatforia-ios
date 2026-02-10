//
//  ContentView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        switch auth.state {
        case .loading:
            SplashView()
        case .loggedOut:
            LoginView()
        case .loggedIn(let user):
            AppShellView(user: user)
        }
    }
}
