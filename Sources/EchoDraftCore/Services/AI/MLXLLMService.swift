import Foundation
import MLXLLM
import MLXLMCommon

/// mlx-swift-lm backed chat/summary; downloads weights on first use via Hugging Face hub cache.
@MainActor
public final class MLXLLMService: LLMGenerating {
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
        let session = ChatSession(c, instructions: instructions)
        return try await session.respond(to: transcript)
    }

    public func chat(transcript: String, question: String) async throws -> String {
        guard let c = container else {
            throw NSError(
                domain: "MLXLLMService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded; call ensureLoaded first."]
            )
        }
        let session = ChatSession(
            c,
            instructions: "Answer using only the transcript as context. If unsure, say you don't know."
        )
        let prompt = "Transcript:\n\n\(transcript)\n\nQuestion:\n\(question)"
        return try await session.respond(to: prompt)
    }
}
