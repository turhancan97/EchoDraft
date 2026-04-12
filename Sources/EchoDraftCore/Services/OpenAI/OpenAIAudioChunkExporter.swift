import AVFoundation
import Foundation

/// Splits extracted audio so each upload stays under OpenAI’s per-request limit (~25 MB); avoids HTTP 413.
public enum OpenAIAudioChunkExporter {
    /// Target max size per chunk (below API 25 MB limit; leaves room for multipart overhead).
    public static let maxUploadBytes: Int64 = 20 * 1024 * 1024

    /// Max duration per transcription request. Longer recordings are split even when under
    /// ``maxUploadBytes`` so `gpt-4o-transcribe-diarize` can finish within server/client time limits.
    public static let maxChunkDurationSeconds: Double = 5 * 60

    /// Minimum segment duration before we stop splitting (avoid infinite recursion on tiny slices).
    private static let minSplitSeconds: Double = 15

    public struct Chunk: Sendable {
        public let fileURL: URL
        public let timeOffsetSeconds: Double
        public let isTemporary: Bool
    }

    /// Builds one or more `.m4a` chunks; originals under both byte and duration caps return one non-temporary chunk.
    public static func makeChunksForUpload(audioFileURL: URL) async throws -> [Chunk] {
        let attrs = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
        let byteSize = attrs[.size] as? Int64 ?? 0

        let asset = AVURLAsset(url: audioFileURL)
        let totalSeconds: Double
        do {
            let durationCM = try await asset.load(.duration)
            totalSeconds = durationCM.seconds
        } catch {
            // Tiny/invalid fixtures (e.g. unit tests) or unreadable media: single upload if under size cap.
            if byteSize <= maxUploadBytes {
                return [
                    Chunk(fileURL: audioFileURL, timeOffsetSeconds: 0, isTemporary: false),
                ]
            }
            throw OpenAIAudioChunkError.invalidDuration
        }

        guard totalSeconds.isFinite, totalSeconds > 0 else {
            if byteSize <= maxUploadBytes {
                return [
                    Chunk(fileURL: audioFileURL, timeOffsetSeconds: 0, isTemporary: false),
                ]
            }
            throw OpenAIAudioChunkError.invalidDuration
        }

        // Under byte cap and short enough for one API call (diarization is slow on long single requests).
        if byteSize <= maxUploadBytes, totalSeconds <= maxChunkDurationSeconds {
            return [
                Chunk(fileURL: audioFileURL, timeOffsetSeconds: 0, isTemporary: false),
            ]
        }

        var windows: [(start: Double, end: Double)] = []
        var t = 0.0
        while t < totalSeconds {
            let end = min(t + maxChunkDurationSeconds, totalSeconds)
            windows.append((t, end))
            t = end
        }

        var out: [Chunk] = []
        for w in windows {
            let parts = try await exportChunksRecursive(
                asset: asset,
                startSeconds: w.start,
                endSeconds: w.end
            )
            out.append(contentsOf: parts)
        }
        return out
    }

    /// Recursively splits by time until each exported file is under the size cap (handles VBR / long recordings).
    private static func exportChunksRecursive(
        asset: AVURLAsset,
        startSeconds: Double,
        endSeconds: Double
    ) async throws -> [Chunk] {
        let duration = endSeconds - startSeconds
        guard duration > 0.05 else { return [] }

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "echodraft-openai-chunk-\(UUID().uuidString).m4a"
        )
        try await exportSegment(
            asset: asset,
            startSeconds: startSeconds,
            durationSeconds: duration,
            outputURL: outURL
        )

        let sz = (try FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? 0

        if sz <= maxUploadBytes || duration <= minSplitSeconds {
            if sz > maxUploadBytes, duration <= minSplitSeconds {
                try? FileManager.default.removeItem(at: outURL)
                throw OpenAIAudioChunkError.exportFailed(
                    "Even a short slice exceeds the upload size limit — re-encode the source to a smaller file (e.g. lower bitrate M4A) or use Offline mode."
                )
            }
            return [Chunk(fileURL: outURL, timeOffsetSeconds: startSeconds, isTemporary: true)]
        }

        // Still too large: split timeline in half and discard this export.
        try? FileManager.default.removeItem(at: outURL)
        let mid = startSeconds + duration / 2
        let left = try await exportChunksRecursive(asset: asset, startSeconds: startSeconds, endSeconds: mid)
        let right = try await exportChunksRecursive(asset: asset, startSeconds: mid, endSeconds: endSeconds)
        return left + right
    }

    private static func exportSegment(
        asset: AVURLAsset,
        startSeconds: Double,
        durationSeconds: Double,
        outputURL: URL
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else {
            throw OpenAIAudioChunkError.exportFailed("Could not create export session")
        }
        let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: start, duration: duration)
        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw OpenAIAudioChunkError.exportFailed(error.localizedDescription)
        }
    }
}

public enum OpenAIAudioChunkError: Error, LocalizedError {
    case invalidDuration
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Could not read audio duration for splitting."
        case .exportFailed(let msg):
            return "Could not split audio for upload: \(msg)"
        }
    }
}
