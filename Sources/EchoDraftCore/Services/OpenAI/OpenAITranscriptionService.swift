import Foundation

public enum OpenAITranscriptionError: Error, LocalizedError {
    case noAPIKey

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Add an OpenAI API key in Settings to use Online transcription."
        }
    }
}

/// Whisper API transcription; output segments use speaker index 0 until diarization runs.
public final class OpenAITranscriptionService: TranscriptionServicing, @unchecked Sendable {
    private let client: OpenAIClienting
    private let baseURL: @Sendable () -> String
    private let apiKey: @Sendable () -> String?

    public init(
        client: OpenAIClienting = OpenAIClient(),
        baseURL: @escaping @Sendable () -> String,
        apiKey: @escaping @Sendable () -> String?
    ) {
        self.client = client
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public func transcribe(
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment] {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw OpenAITranscriptionError.noAPIKey
        }
        progress(0.05)
        let result = try await client.transcribeAudio(
            fileURL: audioFileURL,
            apiKey: key,
            baseURL: baseURL(),
            progress: { p in
                progress(0.05 + p * 0.94)
            }
        )
        progress(1)
        var out: [TimedTextSegment] = []
        for s in result.segments where !s.text.isEmpty {
            out.append(
                TimedTextSegment(
                    startSeconds: s.start,
                    endSeconds: max(s.start, s.end),
                    text: s.text,
                    speakerIndex: 0
                )
            )
        }
        if out.isEmpty, !result.text.isEmpty {
            let end = result.durationSeconds ?? 0
            out.append(
                TimedTextSegment(
                    startSeconds: 0,
                    endSeconds: end,
                    text: result.text,
                    speakerIndex: 0
                )
            )
        }
        return out
    }
}
