@testable import EchoDraftCore
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

@Test func openAIHTTPStatusDescriptionIsRedacted() {
    let message = OpenAIClientError.httpStatus(500).localizedDescription
    #expect(message.localizedCaseInsensitiveContains("500"))
    #expect(!message.localizedCaseInsensitiveContains("api key"))
    #expect(!message.localizedCaseInsensitiveContains("transcript"))
}

@Test func openAIMultipartUploadUsesFileBackedBody() throws {
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString).m4a")
    let audioBytes = Data([0x00, 0x01, 0xAB, 0xCD, 0xEF])
    try audioBytes.write(to: audioURL)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let boundary = "Boundary-Unit-Test"
    let multipartURL = try OpenAIClient.createMultipartUploadFile(audioFileURL: audioURL, boundary: boundary)
    defer { try? FileManager.default.removeItem(at: multipartURL) }

    let body = try Data(contentsOf: multipartURL)
    #expect(body.count > audioBytes.count)
    #expect(body.containsSubsequence(Data("--\(boundary)\r\n".utf8)))
    #expect(body.containsSubsequence(audioBytes))
    #expect(body.containsSubsequence(Data("name=\"model\"\r\n\r\nwhisper-1\r\n".utf8)))
    #expect(body.containsSubsequence(Data("name=\"response_format\"\r\n\r\nverbose_json\r\n".utf8)))
}

private extension Data {
    func containsSubsequence(_ needle: Data) -> Bool {
        guard !needle.isEmpty else { return true }
        if needle.count > count { return false }
        return self.range(of: needle) != nil
    }
}
