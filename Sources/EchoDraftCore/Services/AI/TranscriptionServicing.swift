import Foundation

public protocol TranscriptionServicing: Sendable {
    /// Produces time-aligned text segments (single speaker ok before diarization).
    func transcribe(
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment]

    /// Drop heavy model weights before a downstream step (e.g. diarization) to reduce peak RAM.
    func releaseTranscriptionResources() async
}

extension TranscriptionServicing {
    public func releaseTranscriptionResources() async {}
}
