import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 1.0
    @State private var logoOpacity: Double = 1.0

    var body: some View {
        ZStack {
            Color(red: 255 / 255, green: 247 / 255, blue: 240 / 255)
                .ignoresSafeArea()

            Image("ChatforiaLaunchLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 110, height: 110)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                logoScale = 0.985
                logoOpacity = 0.96
            }
        }
    }
}
