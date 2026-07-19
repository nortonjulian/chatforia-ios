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

        let recorder = try AVAudioRecorder(
            url: fileURL,
            settings: settings
        )

        guard recorder.prepareToRecord(),
            recorder.record() else {
            try? session.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )

            try? FileManager.default.removeItem(at: fileURL)

            throw NSError(
                domain: "AudioRecorderService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Recording could not be started."
                ]
            )
        }

        self.recorder = recorder
        self.url = fileURL
        self.startedAt = Date()
    }

    func stop() -> VoiceNoteDraft? {
        guard let recorder,
            let fileURL = url else {
            reset()
            return nil
        }

        // Capture this before calling stop().
        let measuredDuration = recorder.currentTime

        let fallbackDuration = Date().timeIntervalSince(
            startedAt ?? Date()
        )

        let duration = max(
            1,
            measuredDuration > 0
                ? measuredDuration
                : fallbackDuration
        )

        recorder.stop()

        self.recorder = nil
        self.url = nil
        self.startedAt = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        return VoiceNoteDraft(
            fileURL: fileURL,
            durationSec: duration
        )
    }

    func cancel() {
        recorder?.stop()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        reset()
    }

    private func reset() {
        recorder = nil
        url = nil
        startedAt = nil
    }
}
