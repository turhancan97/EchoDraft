import Foundation

public struct TimedTextSegment: Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var speakerIndex: Int

    public init(startSeconds: Double, endSeconds: Double, text: String, speakerIndex: Int) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.speakerIndex = speakerIndex
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
