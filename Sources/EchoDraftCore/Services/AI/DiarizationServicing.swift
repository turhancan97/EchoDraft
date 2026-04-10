import Foundation

public protocol DiarizationServicing: Sendable {
    /// Assigns speaker indices to segments (1-based display handled by UI).
    func diarize(segments: [TimedTextSegment]) async throws -> [TimedTextSegment]
}
