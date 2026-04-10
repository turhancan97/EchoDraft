import Foundation

/// Deterministic stub for tests and CI (no MLX GPU).
public struct StubTranscriptionService: TranscriptionServicing {
    public var template: String

    public init(template: String = "Stub transcription.") {
        self.template = template
    }

    public func transcribe(
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment] {
        progress(0.5)
        try await Task.sleep(nanoseconds: 10_000_000)
        progress(1)
        return [
            TimedTextSegment(startSeconds: 0, endSeconds: 1, text: template, speakerIndex: 0),
        ]
    }
}
