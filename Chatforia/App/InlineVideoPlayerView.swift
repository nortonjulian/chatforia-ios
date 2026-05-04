import SwiftUI
import AVKit
import AVFoundation

struct InlineVideoPlayerView: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                configureAudioSessionForPlayback()
                let p = AVPlayer(url: url)
                p.isMuted = false
                player = p
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }

    private func configureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("⚠️ Failed to configure playback audio session:", error)
        }
    }
}
