import Foundation

public protocol TranscriptionServicing: Sendable {
    /// Produces time-aligned text segments (single speaker ok before diarization).
    func transcribe(
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment]
}
