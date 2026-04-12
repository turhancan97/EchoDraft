import Foundation

public enum OpenAILLMError: Error, LocalizedError {
    case noAPIKey

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Add an OpenAI API key in Settings to use Online summaries and chat."
        }
    }
}

/// Chat Completions for summary and Q&A (models not shown in UI).
public final class OpenAILLMService: LLMGenerating, @unchecked Sendable {
    private let client: OpenAIClienting
    private let baseURL: @Sendable () -> String
    private let apiKey: @Sendable () -> String?
    private let chatModel = "gpt-4o-mini"

    public init(
        client: OpenAIClienting = OpenAIClient(),
        baseURL: @escaping @Sendable () -> String,
        apiKey: @escaping @Sendable () -> String?
    ) {
        self.client = client
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public func ensureLoaded(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let k = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty else {
            throw OpenAILLMError.noAPIKey
        }
        progress(1)
    }

    public func summarize(transcript: String, template: SummaryTemplate) async throws -> String {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw OpenAILLMError.noAPIKey
        }
        let instruction: String
        switch template {
        case .bulletPoints:
            instruction =
                "Summarize the following meeting transcript as concise bullet points. Use clear bullets. Transcript:\n\n"
        case .executive:
            instruction =
                "Write a short executive summary (2–4 paragraphs) of the following meeting transcript:\n\n"
        }
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a helpful assistant that summarizes meetings accurately."],
            ["role": "user", "content": instruction + transcript],
        ]
        let out = try await client.chatCompletion(
            apiKey: key,
            baseURL: baseURL(),
            model: chatModel,
            messages: messages,
            temperature: 0.3
        )
        return out.content
    }

    public func chat(transcript: String, question: String) async throws -> String {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw OpenAILLMError.noAPIKey
        }
        let messages: [[String: String]] = [
            ["role": "system", "content": "Answer using only the meeting transcript when possible. If unsure, say so."],
            [
                "role": "user",
                "content": "Transcript:\n\n\(transcript)\n\nQuestion: \(question)",
            ],
        ]
        let out = try await client.chatCompletion(
            apiKey: key,
            baseURL: baseURL(),
            model: chatModel,
            messages: messages,
            temperature: 0.2
        )
        return out.content
    }
}
