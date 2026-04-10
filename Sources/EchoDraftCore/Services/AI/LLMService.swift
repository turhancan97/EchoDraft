import Foundation

public protocol LLMGenerating: Sendable {
    func ensureLoaded(progress: @escaping @Sendable (Double) -> Void) async throws
    func summarize(transcript: String, template: SummaryTemplate) async throws -> String
    func chat(transcript: String, question: String) async throws -> String
}

public enum SummaryTemplate: String, CaseIterable, Sendable {
    case bulletPoints = "Bullet points"
    case executive = "Executive summary"
}

/// Offline-capable stub: replace with `EchoLLMServiceMLX` (mlx-swift-lm) in an Xcode target that links MLX.
public struct StubLLMService: LLMGenerating {
    public init() {}

    public func ensureLoaded(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }

    public func summarize(transcript: String, template: SummaryTemplate) async throws -> String {
        let prefix: String
        switch template {
        case .bulletPoints: prefix = "Summary (bullets):\n"
        case .executive: prefix = "Executive summary:\n"
        }
        return prefix + String(transcript.prefix(2000))
    }

    public func chat(transcript: String, question: String) async throws -> String {
        "Answer (stub): question=\(question); transcriptChars=\(transcript.count)"
    }
}
