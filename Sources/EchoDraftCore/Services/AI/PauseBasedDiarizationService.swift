import Foundation

/// Offline diarization: alternates speakers on sentence-like boundaries (period splits); fast and on-device.
public struct PauseBasedDiarizationService: DiarizationServicing {
    public init() {}

    public func diarize(
        segments: [TimedTextSegment],
        audioFileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedTextSegment] {
        progress(0.5)
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
                        speakerIndex: speaker % 2,
                        speakerLabel: seg.speakerLabel
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
                        speakerIndex: speaker % 2,
                        speakerLabel: seg.speakerLabel
                    ))
                speaker += 1
                t = end
            }
        }
        if out.isEmpty {
            progress(1)
            return segments
        }
        progress(1)
        return out
    }
}
