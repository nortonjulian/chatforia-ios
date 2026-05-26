import Foundation
import AVFoundation

enum MediaPermissionError: LocalizedError {
    case cameraDenied
    case microphoneDenied
    case cameraRestricted
    case microphoneRestricted

    var errorDescription: String? {
        switch self {
        case .cameraDenied:
            return String(localized: "media.cameraDenied")

        case .microphoneDenied:
            return String(localized: "media.microphoneDenied")

        case .cameraRestricted:
            return String(localized: "media.cameraRestricted")

        case .microphoneRestricted:
            return String(localized: "media.microphoneRestricted")
        }
    }
}

@MainActor
final class MediaPermissionManager {
    static let shared = MediaPermissionManager()
    private init() {}

    func ensureVideoCallPermissions() async throws {
        try await ensureMicrophonePermission()
        try await ensureCameraPermission()
    }

    func ensureMicrophonePermission() async throws {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return

            case .denied:
                throw MediaPermissionError.microphoneDenied

            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }

                if !granted {
                    throw MediaPermissionError.microphoneDenied
                }

            @unknown default:
                throw MediaPermissionError.microphoneDenied
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return

            case .denied:
                throw MediaPermissionError.microphoneDenied

            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }

                if !granted {
                    throw MediaPermissionError.microphoneDenied
                }

            @unknown default:
                throw MediaPermissionError.microphoneDenied
            }
        }
    }

    func ensureCameraPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return

        case .denied:
            throw MediaPermissionError.cameraDenied

        case .restricted:
            throw MediaPermissionError.cameraRestricted

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw MediaPermissionError.cameraDenied
            }

        @unknown default:
            throw MediaPermissionError.cameraDenied
        }
    }
}
