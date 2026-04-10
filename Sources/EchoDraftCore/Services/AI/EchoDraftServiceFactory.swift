import Foundation

public enum EchoDraftServiceFactory {
    public static func makeTranscriptionService() -> TranscriptionServicing {
        if EchoDraftMLRuntime.useStubML {
            return StubTranscriptionService()
        }
        let repo = ProcessInfo.processInfo.environment["ECHODRAFT_STT_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let repo, !repo.isEmpty {
            return MLXWhisperTranscriptionService(modelRepo: repo)
        }
        return MLXWhisperTranscriptionService()
    }

    @MainActor
    public static func makeLLMService() -> LLMGenerating {
        if EchoDraftMLRuntime.useStubML {
            return StubLLMService()
        }
        let id = ProcessInfo.processInfo.environment["ECHODRAFT_LLM_MODEL"]
        if let id, !id.isEmpty {
            return MLXLLMService(modelIdentifier: id)
        }
        return MLXLLMService()
    }
}
