//
//  SplashView.swift
//  Chatforia
//
//  Created by Julian Norton on 2/9/26.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Chatforia…")
        }
        .padding()
    }
}

