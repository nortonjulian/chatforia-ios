import SwiftUI
import AVKit
import AVFoundation

struct InlineVideoPlayerView: View {
    let url: URL
    var suspendPlayback: Bool = false

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                configureAudioSessionForPlayback()
                configurePlayer(for: url)
            }
            .onChange(of: url) { _, newURL in
                // A routine grant refresh should not restart active playback.
                // The backend still authorizes every subsequent media request.
                if player?.rate != 0 {
                    return
                }
                configurePlayer(for: newURL)
            }
            .onChange(of: suspendPlayback) { _, suspended in
                if suspended {
                    player?.pause()
                    configurePlayer(for: url)
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }

    private func configurePlayer(for url: URL) {
        player?.pause()
        player?.replaceCurrentItem(with: nil)

        let next = AVPlayer(url: url)
        next.isMuted = false

        if suspendPlayback {
            next.pause()
        }

        player = next
    }

    private func configureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            debugLog("⚠️ Failed to configure playback audio session:", error)
        }
    }
}
