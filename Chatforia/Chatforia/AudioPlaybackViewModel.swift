import Foundation
import AVFoundation
import CoreGraphics
import Combine

@MainActor
final class AudioPlaybackViewModel: NSObject, ObservableObject {
    static let shared = AudioPlaybackViewModel()

    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentURLString: String?
    @Published private(set) var isSpeakerEnabled = false

    private var streamingPlayer: AVPlayer?
    private var voicemailPlayer: AVAudioPlayer?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    private var voicemailTimer: Timer?
    private var voicemailDownloadTask: Task<Void, Never>?
    private var isVoicemailRoutingEnabled = false
    private var currentUsesVoicemailRouting = false

    private override init() {
        super.init()
    }

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

    func togglePlayback(
        urlString: String,
        authToken: String? = nil,
        usesVoicemailRouting: Bool = false
    ) {
        if currentURLString == urlString {
            guard !isLoading else {
                return
            }

            if currentUsesVoicemailRouting {
                toggleVoicemailPlayback()
            } else {
                toggleStreamingPlayback()
            }

            return
        }

        if usesVoicemailRouting {
            loadVoicemailAndPlay(
                urlString: urlString,
                authToken: authToken
            )
        } else {
            loadStreamingAndPlay(
                urlString: urlString,
                authToken: authToken
            )
        }
    }

    func setSpeakerEnabled(
        _ enabled: Bool
    ) {
        isSpeakerEnabled = enabled

        guard isVoicemailRoutingEnabled else {
            return
        }

        applySelectedOutputRoute()
    }

    func displayDuration(fallback: Double?) -> Double {
        if duration > 0 {
            return duration
        }

        return fallback ?? 0
    }

    func seek(to seconds: Double) {
        let safeSeconds = max(
            0,
            min(seconds, duration)
        )

        if currentUsesVoicemailRouting,
           let voicemailPlayer {

            voicemailPlayer.currentTime = safeSeconds
            currentTime = safeSeconds
            return
        }

        guard let streamingPlayer else {
            return
        }

        let time = CMTime(
            seconds: safeSeconds,
            preferredTimescale: 600
        )

        streamingPlayer.seek(to: time)
        currentTime = safeSeconds
    }

    func stop() {
        if currentUsesVoicemailRouting {
            voicemailPlayer?.pause()
            voicemailPlayer?.currentTime = 0
            stopVoicemailTimer()
        } else {
            streamingPlayer?.pause()
            streamingPlayer?.seek(to: .zero)
        }

        isPlaying = false
        currentTime = 0
    }

    func tearDown() {
        clearPlayers()
        disableVoicemailRouting()
        isSpeakerEnabled = false
    }

    private func toggleVoicemailPlayback() {
        guard let voicemailPlayer else {
            return
        }

        enableVoicemailRouting()

        if isPlaying {
            voicemailPlayer.pause()
            stopVoicemailTimer()
            isPlaying = false
        } else {
            applySelectedOutputRoute()
            isPlaying = voicemailPlayer.play()

            if isPlaying {
                startVoicemailTimer()
            }
        }
    }

    private func toggleStreamingPlayback() {
        guard let streamingPlayer else {
            return
        }

        if isPlaying {
            streamingPlayer.pause()
            isPlaying = false
        } else {
            streamingPlayer.play()
            isPlaying = true
        }
    }

    private func loadVoicemailAndPlay(
        urlString: String,
        authToken: String?
    ) {
        guard let url = URL(string: urlString) else {
            return
        }

        clearPlayers()
        disableVoicemailRouting()
        enableVoicemailRouting()

        currentUsesVoicemailRouting = true
        currentURLString = urlString
        isLoading = true

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let trimmedToken = authToken?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if let trimmedToken,
           !trimmedToken.isEmpty {

            request.setValue(
                "Bearer \(trimmedToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        voicemailDownloadTask =
            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let (data, response) =
                        try await URLSession.shared.data(
                            for: request
                        )

                    guard !Task.isCancelled else {
                        return
                    }

                    guard let httpResponse =
                        response as? HTTPURLResponse,
                        (200...299).contains(
                            httpResponse.statusCode
                        ) else {

                        throw URLError(
                            .badServerResponse
                        )
                    }

                    let player =
                        try AVAudioPlayer(data: data)

                    player.delegate = self
                    player.volume = 1.0
                    player.prepareToPlay()

                    self.voicemailPlayer = player
                    self.duration = player.duration
                    self.currentTime = 0
                    self.isLoading = false

                    self.applySelectedOutputRoute()

                    self.isPlaying = player.play()

                    if self.isPlaying {
                        self.startVoicemailTimer()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.isLoading = false
                    self.isPlaying = false
                    self.currentTime = 0
                    self.duration = 0

                    debugLog(
                        "❌ Voicemail audio failed to load:",
                        error
                    )
                }
            }
    }

    private func loadStreamingAndPlay(
        urlString: String,
        authToken: String?
    ) {
        guard let url = URL(string: urlString) else {
            return
        }

        clearPlayers()
        disableVoicemailRouting()

        currentUsesVoicemailRouting = false
        currentURLString = urlString
        isLoading = true

        let trimmedToken = authToken?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let item: AVPlayerItem

        if let trimmedToken,
           !trimmedToken.isEmpty {

            let asset = AVURLAsset(
                url: url,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "Authorization":
                            "Bearer \(trimmedToken)"
                    ]
                ]
            )

            item = AVPlayerItem(asset: asset)
        } else {
            item = AVPlayerItem(url: url)
        }

        let player = AVPlayer(playerItem: item)
        player.volume = 1.0

        streamingPlayer = player

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
                    self.streamingPlayer?.play()
                    self.isPlaying = true

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

        timeObserver =
            player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self, weak item] time in
                let seconds =
                    CMTimeGetSeconds(time)

                let safeSeconds =
                    seconds.isFinite
                        ? seconds
                        : 0

                Task {
                    @MainActor
                    [weak self, weak item] in

                    guard let self else {
                        return
                    }

                    self.currentTime =
                        safeSeconds

                    if let item {
                        self.updateDuration(
                            from: item
                        )
                    }
                }
            }

        endObserver =
            NotificationCenter.default.addObserver(
                forName:
                    .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self, weak player] _ in
                Task {
                    @MainActor
                    [weak self, weak player] in

                    guard let self else {
                        return
                    }

                    self.isPlaying = false
                    self.currentTime = 0
                    player?.seek(to: .zero)
                }
            }

        isPlaying = false
    }

    private func clearPlayers() {
        voicemailDownloadTask?.cancel()
        voicemailDownloadTask = nil

        stopVoicemailTimer()

        voicemailPlayer?.stop()
        voicemailPlayer?.delegate = nil
        voicemailPlayer = nil

        if let timeObserver,
           let streamingPlayer {

            streamingPlayer.removeTimeObserver(
                timeObserver
            )
        }

        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(
                endObserver
            )
        }

        endObserver = nil
        statusObserver = nil

        streamingPlayer?.pause()
        streamingPlayer = nil

        currentURLString = nil
        currentUsesVoicemailRouting = false
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
    }

    private func startVoicemailTimer() {
        stopVoicemailTimer()

        voicemailTimer =
            Timer.scheduledTimer(
                withTimeInterval: 0.1,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let voicemailPlayer =
                            self.voicemailPlayer else {
                        return
                    }

                    self.currentTime =
                        voicemailPlayer.currentTime
                    self.duration =
                        voicemailPlayer.duration
                }
            }
    }

    private func stopVoicemailTimer() {
        voicemailTimer?.invalidate()
        voicemailTimer = nil
    }

    private func enableVoicemailRouting() {
        if isVoicemailRoutingEnabled {
            applySelectedOutputRoute()
            return
        }

        let session =
            AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .allowBluetoothA2DP
                ]
            )

            try session.setActive(true)

            isVoicemailRoutingEnabled = true
            applySelectedOutputRoute()
        } catch {
            isVoicemailRoutingEnabled = false

            debugLog(
                "❌ Failed to enable voicemail audio routing:",
                error
            )
        }
    }

    private func applySelectedOutputRoute() {
        let session =
            AVAudioSession.sharedInstance()

        do {
            try session.overrideOutputAudioPort(
                isSpeakerEnabled
                    ? .speaker
                    : .none
            )
        } catch {
            debugLog(
                "❌ Failed to change voicemail audio output:",
                error
            )
        }
    }

    private func disableVoicemailRouting() {
        guard isVoicemailRoutingEnabled else {
            return
        }

        let session =
            AVAudioSession.sharedInstance()

        do {
            try session.overrideOutputAudioPort(.none)

            try session.setActive(
                false,
                options:
                    .notifyOthersOnDeactivation
            )
        } catch {
            debugLog(
                "❌ Failed to release voicemail audio routing:",
                error
            )
        }

        isVoicemailRoutingEnabled = false
    }

    private func updateDuration(
        from item: AVPlayerItem
    ) {
        let seconds =
            CMTimeGetSeconds(item.duration)

        if seconds.isFinite,
           seconds > 0 {

            duration = seconds
            isLoading = false
        }
    }
}

extension AudioPlaybackViewModel:
    AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.stopVoicemailTimer()
            self.isPlaying = false
            self.currentTime = 0
            player.currentTime = 0
            self.disableVoicemailRouting()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.stopVoicemailTimer()
            self.isPlaying = false
            self.isLoading = false

            debugLog(
                "❌ Voicemail audio decode failed:",
                error as Any
            )
        }
    }
}
