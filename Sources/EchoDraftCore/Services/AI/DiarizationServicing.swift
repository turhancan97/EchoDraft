import Foundation

public protocol DiarizationServicing: Sendable {
    /// Assigns speaker indices to segments (1-based display handled by UI).
    /// - Parameters:
    ///   - audioFileURL: Extracted mono/capture audio (some implementations ignore it; kept for a uniform API).
    ///   - progress: Sub-progress within the diarization phase (0…1).
    func diarize(
        segments: [TimedTextSegment],
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment]
}
