import Foundation

public struct TimedTextSegment: Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var speakerIndex: Int
    /// Persisted speaker name when set (e.g. online diarization). Otherwise UI uses `"Speaker \(speakerIndex + 1)"`.
    public var speakerLabel: String?

    public init(
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        speakerIndex: Int,
        speakerLabel: String? = nil
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.speakerIndex = speakerIndex
        self.speakerLabel = speakerLabel
    }
}

public enum ProcessingJobState: Equatable, Sendable {
    case idle
    case queued
    case running(progress: Double)
    case paused
    case cancelled
    case failed(String)
    case completed
}
