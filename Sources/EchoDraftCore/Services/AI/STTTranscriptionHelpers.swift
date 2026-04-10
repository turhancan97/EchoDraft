import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

func envFloat(_ s: String?) -> Float? {
    guard let s, !s.isEmpty, let v = Float(s) else { return nil }
    return v
}

func sttDouble(_ value: Any?) -> Double? {
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

enum STTTranscriptionHelpers {
    static func prepareMonoAudioForSTT(
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

    static func estimateDurationSeconds(samples: MLXArray, sampleRate: Int) -> Double {
        let n = samples.ndim > 0 ? samples.dim(-1) : 0
        guard sampleRate > 0, n > 0 else { return 0 }
        return Double(n) / Double(sampleRate)
    }

    static func timedSegments(from output: STTOutput, fallbackDuration: Double) -> [TimedTextSegment] {
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
