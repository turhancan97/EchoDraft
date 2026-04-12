import Foundation

/// Returns segments unchanged (e.g. online transcription already includes speaker diarization).
public struct PassthroughDiarizationService: DiarizationServicing {
    public init() {}

    public func diarize(segments: [TimedTextSegment]) async throws -> [TimedTextSegment] {
        segments
    }
}
