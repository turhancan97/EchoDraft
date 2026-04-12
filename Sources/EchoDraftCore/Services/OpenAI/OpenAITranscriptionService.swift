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

/// OpenAI `gpt-4o-transcribe-diarize` transcription; long files are split to stay under the API size limit (HTTP 413).
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
        progress(0.02)

        let chunks = try await OpenAIAudioChunkExporter.makeChunksForUpload(audioFileURL: audioFileURL)
        defer {
            for c in chunks where c.isTemporary {
                try? FileManager.default.removeItem(at: c.fileURL)
            }
        }

        let baseURL = baseURL()
        var merged: [TimedTextSegment] = []
        let total = max(1, chunks.count)

        var speakerKeyToIndex: [String: Int] = [:]
        var nextSpeakerIndex = 0

        func speakerIndex(forKey key: String) -> Int {
            if let i = speakerKeyToIndex[key] { return i }
            let i = nextSpeakerIndex
            nextSpeakerIndex += 1
            speakerKeyToIndex[key] = i
            return i
        }

        for (chunkIdx, chunk) in chunks.enumerated() {
            let chunkIndex = chunkIdx
            let result = try await client.transcribeAudio(
                fileURL: chunk.fileURL,
                apiKey: key,
                baseURL: baseURL,
                progress: { p in
                    let slice = (Double(chunkIndex) + p) / Double(total)
                    progress(0.02 + slice * 0.96)
                }
            )

            let offset = chunk.timeOffsetSeconds
            var hadSegments = false
            for s in result.segments where !s.text.isEmpty {
                hadSegments = true
                let rawKey = s.speakerKey ?? "0"
                let spk = speakerIndex(forKey: rawKey)
                let label = "Speaker \(spk + 1)"
                merged.append(
                    TimedTextSegment(
                        startSeconds: s.start + offset,
                        endSeconds: max(s.start, s.end) + offset,
                        text: s.text,
                        speakerIndex: spk,
                        speakerLabel: label
                    )
                )
            }

            if !hadSegments, !result.text.isEmpty {
                let end = (result.durationSeconds ?? 0) + offset
                let spk = speakerIndex(forKey: "0")
                merged.append(
                    TimedTextSegment(
                        startSeconds: offset,
                        endSeconds: end,
                        text: result.text,
                        speakerIndex: spk,
                        speakerLabel: "Speaker \(spk + 1)"
                    )
                )
            }
        }

        progress(1)
        return merged
    }
}
