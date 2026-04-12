import EchoDraftCore
import Foundation
import Testing

@Test func cancelWhilePausedCancelsImmediatelyWithoutResume() async throws {
    let sourceURL = try makeTempFile(named: "source-\(UUID().uuidString).m4a", bytes: Data([0x01]))
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let extractedDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
    let extractedURL = extractedDir.appendingPathComponent("audio.m4a")
    try Data([0x02]).write(to: extractedURL)

    let transcriberState = TestTranscriberState()
    let queue = ProcessingQueue(
        extract: TestExtractor(extractedAudioURL: extractedURL),
        offlineTranscribe: TestTranscriber(state: transcriberState, shouldThrow: false),
        onlineTranscribe: TestTranscriber(state: transcriberState, shouldThrow: false),
        diarize: PassthroughDiarizer()
    )
    let recorder = QueueStateRecorder()
    await queue.setOnStateChange { _, state in
        await recorder.append(state)
    }

    await queue.pause()
    let enqueueTask = Task {
        try await queue.enqueue(sourceURL, mode: .offline)
    }

    let sawPaused = await waitUntil(timeoutSeconds: 2) {
        await recorder.containsPaused
    }
    #expect(sawPaused)

    await queue.cancelActive()

    let sawCancelled = await waitUntil(timeoutSeconds: 2) {
        await recorder.containsCancelled
    }
    #expect(sawCancelled)
    #expect(await transcriberState.callCount == 0)

    _ = try await enqueueTask.value
}

@Test func queueCleansExtractedAudioOnSuccess() async throws {
    let sourceURL = try makeTempFile(named: "source-\(UUID().uuidString).m4a", bytes: Data([0x01]))
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let extractedDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
    let extractedURL = extractedDir.appendingPathComponent("audio.m4a")
    try Data([0x02]).write(to: extractedURL)

    let queue = ProcessingQueue(
        extract: TestExtractor(extractedAudioURL: extractedURL),
        offlineTranscribe: TestTranscriber(state: TestTranscriberState(), shouldThrow: false),
        onlineTranscribe: TestTranscriber(state: TestTranscriberState(), shouldThrow: false),
        diarize: PassthroughDiarizer()
    )

    _ = try await queue.enqueue(sourceURL, mode: .offline)

    #expect(!FileManager.default.fileExists(atPath: extractedURL.path))
    #expect(!FileManager.default.fileExists(atPath: extractedDir.path))
}

@Test func queueCleansExtractedAudioOnFailure() async throws {
    let sourceURL = try makeTempFile(named: "source-\(UUID().uuidString).m4a", bytes: Data([0x01]))
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let extractedDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
    let extractedURL = extractedDir.appendingPathComponent("audio.m4a")
    try Data([0x02]).write(to: extractedURL)

    let queue = ProcessingQueue(
        extract: TestExtractor(extractedAudioURL: extractedURL),
        offlineTranscribe: TestTranscriber(state: TestTranscriberState(), shouldThrow: true),
        onlineTranscribe: TestTranscriber(state: TestTranscriberState(), shouldThrow: true),
        diarize: PassthroughDiarizer()
    )
    let recorder = QueueStateRecorder()
    await queue.setOnStateChange { _, state in
        await recorder.append(state)
    }

    _ = try await queue.enqueue(sourceURL, mode: .offline)
    let sawFailure = await waitUntil(timeoutSeconds: 2) {
        await recorder.containsFailed
    }
    #expect(sawFailure)
    #expect(!FileManager.default.fileExists(atPath: extractedURL.path))
    #expect(!FileManager.default.fileExists(atPath: extractedDir.path))
}

private actor QueueStateRecorder {
    private var states: [ProcessingJobState] = []

    func append(_ state: ProcessingJobState) {
        states.append(state)
    }

    var containsPaused: Bool {
        states.contains { state in
            if case .paused = state { return true }
            return false
        }
    }

    var containsCancelled: Bool {
        states.contains { state in
            if case .cancelled = state { return true }
            return false
        }
    }

    var containsFailed: Bool {
        states.contains { state in
            if case .failed = state { return true }
            return false
        }
    }
}

private actor TestTranscriberState {
    private(set) var callCount: Int = 0

    func increment() {
        callCount += 1
    }
}

private struct TestExtractor: AudioExtractionServicing {
    let extractedAudioURL: URL

    func extractAudioToTemporaryFile(from mediaURL: URL) async throws -> URL {
        extractedAudioURL
    }

    func durationSeconds(of mediaURL: URL) async throws -> Double {
        1
    }
}

private struct TestTranscriber: TranscriptionServicing {
    let state: TestTranscriberState
    let shouldThrow: Bool

    func transcribe(
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment] {
        await state.increment()
        progress(1)
        if shouldThrow {
            struct TestError: Error {}
            throw TestError()
        }
        return [TimedTextSegment(startSeconds: 0, endSeconds: 1, text: "ok", speakerIndex: 0)]
    }
}

private struct PassthroughDiarizer: DiarizationServicing {
    func diarize(segments: [TimedTextSegment]) async throws -> [TimedTextSegment] {
        segments
    }
}

private func makeTempFile(named name: String, bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try bytes.write(to: url)
    return url
}

private func waitUntil(timeoutSeconds: Double, condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await condition()
}
