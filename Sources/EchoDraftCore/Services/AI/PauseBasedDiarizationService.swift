import Foundation

/// Assigns alternating speakers on sentence-like boundaries (placeholder until MLX diarization is wired).
public struct PauseBasedDiarizationService: DiarizationServicing {
    public init() {}

    public func diarize(segments: [TimedTextSegment]) async throws -> [TimedTextSegment] {
        var out: [TimedTextSegment] = []
        var speaker = 0
        for seg in segments {
            let pieces = seg.text.split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty else {
                out.append(
                    TimedTextSegment(
                        startSeconds: seg.startSeconds,
                        endSeconds: seg.endSeconds,
                        text: seg.text,
                        speakerIndex: speaker % 2
                    ))
                continue
            }
            let span = max(0.01, (seg.endSeconds - seg.startSeconds) / Double(max(1, pieces.count)))
            var t = seg.startSeconds
            for (i, p) in pieces.enumerated() {
                let txt = String(p).trimmingCharacters(in: .whitespacesAndNewlines)
                if txt.isEmpty { continue }
                let end = i == pieces.count - 1 ? seg.endSeconds : min(seg.endSeconds, t + span)
                out.append(
                    TimedTextSegment(
                        startSeconds: t,
                        endSeconds: end,
                        text: txt + (i < pieces.count - 1 && !txt.hasSuffix(".") ? "." : ""),
                        speakerIndex: speaker % 2
                    ))
                speaker += 1
                t = end
            }
        }
        if out.isEmpty { return segments }
        return out
    }
}
