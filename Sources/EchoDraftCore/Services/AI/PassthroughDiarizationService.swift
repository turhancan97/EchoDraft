import Foundation

/// Returns segments unchanged (e.g. online transcription already includes speaker diarization).
public struct PassthroughDiarizationService: DiarizationServicing {
    public init() {}

    public func diarize(
        segments: [TimedTextSegment],
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment] {
        progress(1)
        return segments
    }
}
