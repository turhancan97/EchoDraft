import EchoDraftCore
import Foundation
import Testing

struct MockOpenAIClient: OpenAIClienting {
    var transcribeResult: TranscriptionResult = TranscriptionResult(
        text: "hello",
        segments: [TranscriptionSegmentDTO(start: 0, end: 1, text: "hello")],
        durationSeconds: 1
    )
    var chatResult = ChatCompletionResult(content: "ok", promptTokens: 1, completionTokens: 2)

    func transcribeAudio(
        fileURL: URL,
        apiKey: String,
        baseURL: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        progress(1)
        return transcribeResult
    }

    func chatCompletion(
        apiKey: String,
        baseURL: String,
        model: String,
        messages: [[String: String]],
        temperature: Double
    ) async throws -> ChatCompletionResult {
        chatResult
    }
}

@Test func openAITranscriptionMapsSegments() async throws {
    let mock = MockOpenAIClient()
    let svc = OpenAITranscriptionService(
        client: mock,
        baseURL: { "https://api.openai.com" },
        apiKey: { "sk-test" }
    )
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("t.m4a")
    try Data([0]).write(to: tmp)
    let segs = try await svc.transcribe(audioFileURL: tmp) { _ in }
    #expect(segs.count == 1)
    #expect(segs[0].text == "hello")
    try? FileManager.default.removeItem(at: tmp)
}

@Test func queueErrorHumanizesRateLimitMessage() {
    let m = QueueErrorFormatting.humanize("Error 429 rate limit")
    #expect(m.localizedCaseInsensitiveContains("rate limit"))
}
