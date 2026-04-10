import AVFoundation
import Foundation

public protocol AudioExtractionServicing: Sendable {
    /// Returns a file URL to extracted linear PCM / m4a suitable for ML (copied or exported).
    func extractAudioToTemporaryFile(from mediaURL: URL) async throws -> URL
    func durationSeconds(of mediaURL: URL) async throws -> Double
}

public enum AudioExtractionError: Error, Equatable {
    case noAudioTrack
    case exportFailed(String)
}

public final class AudioExtractionService: AudioExtractionServicing, @unchecked Sendable {
    public init() {}

    public func durationSeconds(of mediaURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: mediaURL)
        let sec = try await asset.load(.duration).seconds
        guard sec.isFinite, sec > 0 else { return 0 }
        return sec
    }

    public func extractAudioToTemporaryFile(from mediaURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: mediaURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioExtractionError.noAudioTrack
        }
        let outDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appending(path: "audio.m4a")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else {
            throw AudioExtractionError.exportFailed("Could not create export session")
        }
        session.outputURL = outURL
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            throw AudioExtractionError.exportFailed(session.error?.localizedDescription ?? "unknown")
        }
        return outURL
    }
}
