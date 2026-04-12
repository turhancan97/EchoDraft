import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// MLXAudio STT via ``Qwen3ASRModel`` (mlx-audio-swift). ``modelRepo`` must be a Qwen3-ASR–compatible Hub id
/// (e.g. ``mlx-community/Qwen3-ASR-0.6B-4bit``). Other MLX ASR families (e.g. VibeVoice on Python mlx-audio only) are not loaded here.
public final class MLXWhisperTranscriptionService: TranscriptionServicing, @unchecked Sendable {
    /// Serialized by ``ProcessingQueue`` (one active job); no concurrent loads expected.
    private var cachedModel: Qwen3ASRModel?
    private let modelRepo: String

    public init(modelRepo: String = "mlx-community/Qwen3-ASR-0.6B-4bit") {
        self.modelRepo = modelRepo
    }

    public func transcribe(
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment] {
        progress(0.05)
        let model = try await cachedSTTModel()
        progress(0.15)
        let (inputSampleRate, inputAudio) = try loadAudioArray(from: audioFileURL)
        let audio = try STTTranscriptionHelpers.prepareMonoAudioForSTT(
            inputAudio,
            inputSampleRate: inputSampleRate,
            targetSampleRate: 16_000
        )
        progress(0.25)
        let genParams = Self.effectiveSTTParameters(from: model.defaultGenerationParameters)
        progress(0.35)
        let output = model.generate(audio: audio, generationParameters: genParams)
        progress(0.95)
        let fallbackDuration = STTTranscriptionHelpers.estimateDurationSeconds(samples: audio, sampleRate: 16_000)
        let segments = STTTranscriptionHelpers.timedSegments(from: output, fallbackDuration: fallbackDuration)
        progress(1)
        return segments
    }

    /// Applies optional ``ProcessInfo`` overrides for RAM/latency tradeoffs (see README).
    private static func effectiveSTTParameters(from defaults: STTGenerateParameters) -> STTGenerateParameters {
        let env = ProcessInfo.processInfo.environment
        var chunk = defaults.chunkDuration
        if let v = envFloat(env["ECHODRAFT_STT_CHUNK_DURATION_SEC"]) {
            // Smaller chunks → lower peak memory on long files, more chunk boundaries (may slow total time).
            chunk = min(max(v, 15), 1200)
        }
        var minChunk = defaults.minChunkDuration
        if let v = envFloat(env["ECHODRAFT_STT_MIN_CHUNK_DURATION_SEC"]) {
            minChunk = min(max(v, 0.5), 60)
        }
        var maxTok = defaults.maxTokens
        if let s = env["ECHODRAFT_STT_MAX_TOKENS"], let v = Int(s), v > 0 {
            maxTok = min(max(v, 256), 8192)
        }
        let lang: String?
        if let l = env["ECHODRAFT_STT_LANGUAGE"], !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lang = l.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            lang = defaults.language
        }
        return STTGenerateParameters(
            maxTokens: maxTok,
            temperature: defaults.temperature,
            topP: defaults.topP,
            topK: defaults.topK,
            verbose: false,
            language: lang,
            chunkDuration: chunk,
            minChunkDuration: minChunk
        )
    }

    private func cachedSTTModel() async throws -> Qwen3ASRModel {
        if let cachedModel {
            return cachedModel
        }
        let loaded = try await Qwen3ASRModel.fromPretrained(modelRepo)
        cachedModel = loaded
        return loaded
    }

}
