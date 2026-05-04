import Combine
import Foundation
@preconcurrency import AVFoundation

enum VideoCompressionError: LocalizedError {
    case missingVideoTrack
    case exportSessionUnavailable
    case exportFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "Video track not found."
        case .exportSessionUnavailable:
            return "Could not create compression session."
        case .exportFailed(let message):
            return "Compression failed: \(message)"
        case .outputMissing:
            return "Compressed video file is missing."
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

final class VideoCompressionService {
    static let shared = VideoCompressionService()
    private init() {}
    
    /// Compresses a picked movie file to MP4 using a medium-quality preset.
    /// Returns a local temp file URL for the compressed video.
    func compressVideo(at inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        
        guard try await asset.loadTracks(withMediaType: .video).isEmpty == false else {
            throw VideoCompressionError.missingVideoTrack
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            throw VideoCompressionError.exportSessionUnavailable
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatforia-video-\(UUID().uuidString).mp4")
        
        // clean up existing temp file if needed
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        try await export(exportSession, to: outputURL)
        
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VideoCompressionError.outputMissing
        }
        
        return outputURL
    }
    
    private func export(_ session: AVAssetExportSession, to outputURL: URL) async throws {
        if #available(iOS 18.0, *) {
            try await session.export(to: outputURL, as: .mp4)
        } else {
            let box = ExportSessionBox(session)

            try await withCheckedThrowingContinuation { continuation in
                box.session.exportAsynchronously {
                    let status = box.session.status
                    let errorMessage = box.session.error?.localizedDescription ?? "Unknown error"

                    switch status {
                    case .completed:
                        continuation.resume()

                    case .failed:
                        continuation.resume(
                            throwing: VideoCompressionError.exportFailed(errorMessage)
                        )

                    case .cancelled:
                        continuation.resume(
                            throwing: VideoCompressionError.exportFailed("Cancelled")
                        )

                    default:
                        continuation.resume(
                            throwing: VideoCompressionError.exportFailed(
                                "Unexpected export status: \(status.rawValue)"
                            )
                        )
                    }
                }
            }
        }
    }
}
