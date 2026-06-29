import Foundation
import AVFoundation
import UIKit
import AudioToolbox

@MainActor
final class AudioPlayerService {
    static let shared = AudioPlayerService()

    private var player: AVAudioPlayer?
    
    private var lastPlayedAt: Date = .distantPast
    

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
        let now = Date()

        guard now.timeIntervalSince(lastPlayedAt) > 1.0 else {
            return
        }

        lastPlayedAt = now

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
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        let url =
            Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "sounds/Message_Tones"
            )
            ??
            Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "sounds/Ringtones"
            )
            ??
            Bundle.main.url(
                forResource: name,
                withExtension: ext
            )

        guard let url else {
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
            debugLog("❌ Failed to play sound:", error)
        }
    }
}
