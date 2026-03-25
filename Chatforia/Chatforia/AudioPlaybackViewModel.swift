import Foundation
import AVFoundation
import CoreGraphics
import Combine

@MainActor
final class AudioPlaybackViewModel: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentURLString: String?
    
    var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
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
        if duration > 0 { return duration }
        return fallback ?? 0
    }
    
    func stop() {
        player?.pause()
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
        
        player?.pause()
        player = nil
        currentURLString = nil
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
    }
    
    private func loadAndPlay(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        tearDown()
        
        isLoading = true
        currentTime = 0
        duration = 0
        currentURLString = urlString
        
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard self != nil else { return }
            
            let current = CMTimeGetSeconds(time)
            let resolvedCurrent = current.isFinite ? current : 0
            
            let resolvedDuration: Double = {
                let dur = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
                return (dur.isFinite && dur > 0) ? dur : 0
            }()
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = resolvedCurrent
                if resolvedDuration > 0 {
                    self.duration = resolvedDuration
                    self.isLoading = false
                }
            }
        }
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = 0
                player.seek(to: .zero)
            }
        }
    }
    
}
