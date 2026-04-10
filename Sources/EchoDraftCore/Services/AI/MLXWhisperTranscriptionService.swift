import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// MLXAudio STT (default: Qwen3-ASR) behind ``TranscriptionServicing``.
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
        let audio = try prepareAudioForSTT(inputAudio, inputSampleRate: inputSampleRate, targetSampleRate: 16_000)
        progress(0.25)
        let defaults = model.defaultGenerationParameters
        let genParams = STTGenerateParameters(
            maxTokens: defaults.maxTokens,
            temperature: defaults.temperature,
            topP: defaults.topP,
            topK: defaults.topK,
            verbose: false,
            language: defaults.language,
            chunkDuration: defaults.chunkDuration,
            minChunkDuration: defaults.minChunkDuration
        )
        progress(0.35)
        let output = model.generate(audio: audio, generationParameters: genParams)
        progress(0.95)
        let fallbackDuration = estimateDurationSeconds(samples: audio, sampleRate: 16_000)
        let segments = mapOutput(output, fallbackDuration: fallbackDuration)
        progress(1)
        return segments
    }

    private func cachedSTTModel() async throws -> Qwen3ASRModel {
        if let cachedModel {
            return cachedModel
        }
        let loaded = try await Qwen3ASRModel.fromPretrained(modelRepo)
        cachedModel = loaded
        return loaded
    }

    private func prepareAudioForSTT(
        _ audio: MLXArray,
        inputSampleRate: Int,
        targetSampleRate: Int
    ) throws -> MLXArray {
        let mono = audio.ndim > 1 ? audio.mean(axis: -1) : audio
        guard inputSampleRate != targetSampleRate else {
            return mono
        }
        return try resampleAudio(mono, from: inputSampleRate, to: targetSampleRate)
    }

    private func estimateDurationSeconds(samples: MLXArray, sampleRate: Int) -> Double {
        let n = samples.ndim > 0 ? samples.dim(-1) : 0
        guard sampleRate > 0, n > 0 else { return 0 }
        return Double(n) / Double(sampleRate)
    }

    private func mapOutput(_ output: STTOutput, fallbackDuration: Double) -> [TimedTextSegment] {
        if let raw = output.segments, !raw.isEmpty {
            let mapped: [TimedTextSegment] = raw.compactMap { item in
                guard let text = item["text"] as? String else { return nil }
                let start = sttDouble(item["start"]) ?? 0
                let end = sttDouble(item["end"]) ?? max(start, fallbackDuration)
                return TimedTextSegment(
                    startSeconds: start,
                    endSeconds: end,
                    text: text,
                    speakerIndex: 0
                )
            }
            if !mapped.isEmpty {
                return mapped
            }
        }
        let end = max(fallbackDuration, 0.01)
        return [
            TimedTextSegment(
                startSeconds: 0,
                endSeconds: end,
                text: output.text,
                speakerIndex: 0
            ),
        ]
    }
}

private func sttDouble(_ value: Any?) -> Double? {
    switch value {
    case let v as Double:
        return v
    case let v as Float:
        return Double(v)
    case let v as Int:
        return Double(v)
    case let v as NSNumber:
        return v.doubleValue
    case let v as String:
        return Double(v)
    default:
        return nil
    }
}
