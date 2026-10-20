import Foundation
import AVFoundation

// Recorder and blocking session operations execute on this actor, never the UI actor.
actor AudioRecorderService {
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var generation = 0
    private var isStarting = false
    private var ownsSession = false
    private var startedAt: Date?

    @MainActor
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
        guard recorder == nil, !isStarting else { throw recordingError() }
        isStarting = true
        defer { isStarting = false }
        generation += 1
        let revision = generation
        let granted = await requestPermissionIfNeeded()
        guard revision == generation, !Task.isCancelled else { throw CancellationError() }
        guard granted else {
            throw NSError(
                domain: "AudioRecorderService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied."]
            )
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            ownsSession = true
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let created = try AVAudioRecorder(url: fileURL, settings: settings)
            guard created.prepareToRecord(), created.record() else {
                created.stop()
                throw recordingError()
            }
            recorder = created
            url = fileURL
            startedAt = Date()
        } catch {
            deactivateIfOwned()
            try? FileManager.default.removeItem(at: fileURL)
            reset()
            throw error
        }
    }

    func stop() -> VoiceNoteDraft? {
        generation += 1
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

        deactivateIfOwned()

        return VoiceNoteDraft(
            fileURL: fileURL,
            durationSec: duration
        )
    }

    func cancel() {
        generation += 1
        recorder?.stop()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        deactivateIfOwned()

        reset()
    }

    private func recordingError() -> NSError {
        NSError(domain: "AudioRecorderService", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Recording could not be started."])
    }

    private func deactivateIfOwned() {
        guard ownsSession else { return }
        ownsSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func reset() {
        recorder = nil
        url = nil
        startedAt = nil
    }
}
