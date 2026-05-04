import Foundation
import AVFoundation

final class AudioRecorderService {
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var startedAt: Date?

    func requestPermissionIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
    }

    func start() async throws {
        let granted = await requestPermissionIfNeeded()
        guard granted else {
            throw NSError(
                domain: "AudioRecorderService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied."]
            )
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw NSError(
                domain: "AudioRecorderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Recording could not be started."]
            )
        }

        self.recorder = recorder
        self.url = fileURL
        self.startedAt = Date()
    }

    func stop() -> VoiceNoteDraft? {
        recorder?.stop()

        guard let fileURL = url else {
            reset()
            return nil
        }

        let duration = max(1, recorder?.currentTime ?? Date().timeIntervalSince(startedAt ?? Date()))

        let draft = VoiceNoteDraft(
            fileURL: fileURL,
            durationSec: duration
        )

        reset(keepFile: true)
        return draft
    }

    func cancel() {
        recorder?.stop()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        reset()
    }

    private func reset(keepFile: Bool = false) {
        recorder = nil
        startedAt = nil

        if !keepFile {
            url = nil
        }
    }
}
