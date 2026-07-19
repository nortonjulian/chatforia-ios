import Foundation
import AVFoundation
import CoreGraphics
import Combine

@MainActor
final class AudioPlaybackViewModel: ObservableObject {
    static let shared = AudioPlaybackViewModel()

    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentURLString: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    private init() {}

    var progress: CGFloat {
        guard duration > 0 else {
            return 0
        }

        return CGFloat(
            min(max(currentTime / duration, 0), 1)
        )
    }

    func isCurrent(urlString: String) -> Bool {
        currentURLString == urlString
    }

    func togglePlayback(urlString: String) {
        if currentURLString == urlString, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }

            return
        }

        loadAndPlay(urlString: urlString)
    }

    func displayDuration(fallback: Double?) -> Double {
        if duration > 0 {
            return duration
        }

        return fallback ?? 0
    }

    func seek(to seconds: Double) {
        guard let player else {
            return
        }

        let safeSeconds = max(
            0,
            min(seconds, duration)
        )

        let time = CMTime(
            seconds: safeSeconds,
            preferredTimescale: 600
        )

        player.seek(to: time)
        currentTime = safeSeconds
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)

        isPlaying = false
        currentTime = 0
    }

    func tearDown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }

        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        endObserver = nil
        statusObserver = nil

        player?.pause()
        player = nil

        currentURLString = nil
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
    }

    private func loadAndPlay(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        tearDown()

        currentURLString = urlString
        isLoading = true

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)

        player = newPlayer

        statusObserver = item.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.updateDuration(from: item)

                case .failed:
                    self.isLoading = false
                    self.isPlaying = false
                    self.currentTime = 0
                    self.duration = 0

                    debugLog(
                        "❌ Audio attachment failed to load:",
                        item.error as Any
                    )

                case .unknown:
                    break

                @unknown default:
                    break
                }
            }
        }

        let interval = CMTime(
            seconds: 0.25,
            preferredTimescale: 600
        )

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self, weak item] time in
            let seconds = CMTimeGetSeconds(time)
            let safeSeconds = seconds.isFinite ? seconds : 0

            Task { @MainActor [weak self, weak item] in
                guard let self else {
                    return
                }

                self.currentTime = safeSeconds

                if let item {
                    self.updateDuration(from: item)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak newPlayer] _ in
            Task { @MainActor [weak self, weak newPlayer] in
                guard let self else {
                    return
                }

                self.isPlaying = false
                self.currentTime = 0
                newPlayer?.seek(to: .zero)
            }
        }

        newPlayer.play()
        isPlaying = true
    }

    private func updateDuration(from item: AVPlayerItem) {
        let seconds = CMTimeGetSeconds(item.duration)

        if seconds.isFinite, seconds > 0 {
            duration = seconds
            isLoading = false
        }
    }
}