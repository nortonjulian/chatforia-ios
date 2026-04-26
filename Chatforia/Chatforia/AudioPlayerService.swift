import Foundation
import AVFoundation
import UIKit

@MainActor
final class AudioPlayerService {
    static let shared = AudioPlayerService()

    private var player: AVAudioPlayer?

    private let messageToneKey = "chatforia.messageTone"
    private let ringtoneKey = "chatforia.ringtone"
    private let soundVolumeKey = "chatforia.soundVolume"

    private init() {}

    func save(messageTone: String, ringtone: String, soundVolume: Int) {
        UserDefaults.standard.set(messageTone, forKey: messageToneKey)
        UserDefaults.standard.set(ringtone, forKey: ringtoneKey)
        UserDefaults.standard.set(soundVolume, forKey: soundVolumeKey)
    }

    func playCurrentMessageTone() {
        let filename = UserDefaults.standard.string(forKey: messageToneKey) ?? "Default.mp3"
        let volume = UserDefaults.standard.object(forKey: soundVolumeKey) as? Int ?? 70
        playSound(filename: filename, volume: volume)
    }

    func previewMessageTone(filename: String, volume: Int) {
        playSound(filename: filename, volume: volume)
    }

    func previewRingtone(filename: String, volume: Int) {
        playSound(filename: filename, volume: volume)
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func playSound(filename: String, volume: Int) {
        stop()

        guard filename.lowercased() != "vibrate.mp3" else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            return
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("❌ Audio file not found in bundle:", filename)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.volume = Float(max(0, min(volume, 100))) / 100.0
            audioPlayer.prepareToPlay()
            audioPlayer.play()

            player = audioPlayer
        } catch {
            print("❌ Failed to play sound:", error)
        }
    }
}
