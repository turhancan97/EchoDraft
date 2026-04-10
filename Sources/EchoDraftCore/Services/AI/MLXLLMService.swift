import Foundation
import MLXLLM
import MLXLMCommon

/// mlx-swift-lm backed chat/summary; downloads weights on first use via Hugging Face hub cache.
///
/// Not `@MainActor`: generation can take a long time and must not block the main actor / UI.
/// Callers should run one request at a time (the UI disables actions while ``LLMWorkPhase`` is active).
public final class MLXLLMService: LLMGenerating, @unchecked Sendable {
    /// Caps generation so inference always stops (default `GenerateParameters` has no max; some models rarely emit EOS).
    private static let summaryParameters = GenerateParameters(maxTokens: 768, temperature: 0)
    private static let chatParameters = GenerateParameters(maxTokens: 512, temperature: 0.2)

    private var container: ModelContainer?
    private let modelIdentifier: String

    public init(modelIdentifier: String = LLMRegistry.smolLM_135M_4bit.name) {
        self.modelIdentifier = modelIdentifier
    }

    public func ensureLoaded(progress: @escaping @Sendable (Double) -> Void) async throws {
        if container != nil {
            progress(1)
            return
        }
        let config = ModelConfiguration(id: modelIdentifier)
        let c = try await LLMModelFactory.shared.loadContainer(
            hub: defaultHubApi,
            configuration: config,
            progressHandler: { p in
                progress(p.fractionCompleted)
            }
        )
        container = c
    }

    public func summarize(transcript: String, template: SummaryTemplate) async throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.emptyTranscriptMessage
        }
        guard let c = container else {
            throw NSError(
                domain: "MLXLLMService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded; call ensureLoaded first."]
            )
        }
        let instructions: String
        switch template {
        case .bulletPoints:
            instructions = "Summarize the transcript as concise bullet points."
        case .executive:
            instructions = "Provide a short executive summary of the transcript."
        }
        let session = ChatSession(
            c,
            instructions: instructions,
            generateParameters: Self.summaryParameters
        )
        let result = try await session.respond(to: trimmed)
        return Self.nonEmptyOrHint(result)
    }

    public func chat(transcript: String, question: String) async throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.emptyTranscriptMessage
        }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return "Enter a question to ask about the transcript."
        }
        guard let c = container else {
            throw NSError(
                domain: "MLXLLMService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded; call ensureLoaded first."]
            )
        }
        let session = ChatSession(
            c,
            instructions: "Answer using only the transcript as context. If unsure, say you don't know.",
            generateParameters: Self.chatParameters
        )
        let prompt = "Transcript:\n\n\(trimmed)\n\nQuestion:\n\(q)"
        let result = try await session.respond(to: prompt)
        return Self.nonEmptyOrHint(result)
    }

    private static let emptyTranscriptMessage =
        "There is no transcript text yet. Import and transcribe audio, or add text to segments, then try again."

    private static func nonEmptyOrHint(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return "The model returned no text. Try again, or pick a different model (ECHODRAFT_LLM_MODEL)."
        }
        return s
    }
}
