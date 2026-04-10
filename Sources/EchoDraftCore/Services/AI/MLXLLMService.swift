import Foundation
import MLXLLM
import MLXLMCommon

/// mlx-swift-lm backed chat/summary; downloads weights on first use via Hugging Face hub cache.
///
/// Not `@MainActor`: generation can take a long time and must not block the main actor / UI.
/// Callers should run one request at a time (the UI disables actions while ``LLMWorkPhase`` is active).
public final class MLXLLMService: LLMGenerating, @unchecked Sendable {
    /// Smaller models (e.g. 135M) often collapse into repetitive token soup; repetitionPenalty reduces that.
    private static let summaryParameters = GenerateParameters(
        maxTokens: 384,
        temperature: 0,
        repetitionPenalty: 1.12,
        repetitionContextSize: 64
    )
    private static let chatParameters = GenerateParameters(
        maxTokens: 256,
        temperature: 0,
        repetitionPenalty: 1.12,
        repetitionContextSize: 64
    )

    /// Very long transcripts (e.g. broken ASR loops) confuse small models and blow context; clip for LLM calls.
    private static let maxTranscriptCharactersForLLM = 24_000

    private var container: ModelContainer?
    private let modelIdentifier: String

    /// Default: Phi-3.5 Mini Instruct — far more stable than SmolLM-135M for summarization and Q&A.
    public init(modelIdentifier: String = LLMRegistry.phi3_5_4bit.name) {
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
        let (body, clipNote) = Self.clipTranscriptForLLM(trimmed)
        let instructions: String
        switch template {
        case .bulletPoints:
            instructions = Self.summaryInstructionsBullets
        case .executive:
            instructions = Self.summaryInstructionsExecutive
        }
        let session = ChatSession(
            c,
            instructions: instructions,
            generateParameters: Self.summaryParameters
        )
        let userContent = clipNote + body
        let result = try await session.respond(to: userContent)
        return Self.nonEmptyOrHint(Self.sanitizeModelOutput(result))
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
        let (body, clipNote) = Self.clipTranscriptForLLM(trimmed)
        let session = ChatSession(
            c,
            instructions: Self.chatSystemInstructions,
            generateParameters: Self.chatParameters
        )
        let prompt = "\(clipNote)Transcript:\n\n\(body)\n\nQuestion:\n\(q)"
        let result = try await session.respond(to: prompt)
        return Self.nonEmptyOrHint(Self.sanitizeModelOutput(result))
    }

    private static let emptyTranscriptMessage =
        "There is no transcript text yet. Import and transcribe audio, or add text to segments, then try again."

    private static let summaryInstructionsBullets =
        """
        Summarize only what appears in the user's message (the transcript). Output concise bullet points. \
        Do not invent facts. If the text is repetitive or unclear, say so briefly instead of making things up.
        """

    private static let summaryInstructionsExecutive =
        """
        Write a short executive summary of only what appears in the user's message (the transcript). \
        Do not invent facts. If the text is repetitive or unclear, say so briefly instead of making things up.
        """

    private static let chatSystemInstructions =
        """
        Answer the question using only information that appears in the transcript in the user's message. \
        Do not use outside knowledge or the web. If the transcript does not contain enough information \
        to answer, reply with exactly: Not mentioned in the transcript.
        """

    /// If transcript exceeds ``maxTranscriptCharactersForLLM``, keep start + end so the model still sees structure.
    private static func clipTranscriptForLLM(_ full: String) -> (text: String, prefixNote: String) {
        let max = maxTranscriptCharactersForLLM
        guard full.count > max else {
            return (full, "")
        }
        let half = max / 2
        let head = String(full.prefix(half))
        let tail = String(full.suffix(half))
        let omitted = full.count - half * 2
        let note =
            "[Transcript truncated for the model: \(omitted) characters omitted from the middle.]\n\n"
        return (head + "\n\n…\n\n" + tail, note)
    }

    /// Detects repetitive “word salad” common with tiny LMs or bad context; returns a helpful message instead.
    private static func sanitizeModelOutput(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return raw }
        if looksDegenerate(t) {
            return """
            The language model produced repetitive, unusable text (a known issue with very small models or noisy transcripts). \
            Try again after editing the transcript, or set environment variable ECHODRAFT_LLM_MODEL to a larger mlx-community \
            instruct model (for example Qwen2.5-1.5B-Instruct-4bit) if your Mac has enough memory.
            """
        }
        return raw
    }

    /// Heuristic: one token dominates, or vocabulary is tiny vs length → likely degenerate generation.
    private static func looksDegenerate(_ text: String) -> Bool {
        guard text.count >= 60 else { return false }
        let tokens = text.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }
        guard tokens.count >= 20 else { return false }
        var counts: [String: Int] = [:]
        counts.reserveCapacity(32)
        for tok in tokens {
            let key = String(tok.prefix(48)).lowercased()
            counts[key, default: 0] += 1
        }
        let maxRepeat = counts.values.max() ?? 0
        if Double(maxRepeat) / Double(tokens.count) >= 0.18 {
            return true
        }
        let uniqueRatio = Double(counts.count) / Double(tokens.count)
        return uniqueRatio < 0.14
    }

    private static func nonEmptyOrHint(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return "The model returned no text. Try again, or pick a different model (ECHODRAFT_LLM_MODEL)."
        }
        return s
    }
}
