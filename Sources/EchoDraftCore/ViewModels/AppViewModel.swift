import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class AppViewModel {
    public var recordings: [Recording] = []
    public var selectedRecording: Recording?
    public var searchQuery: String = ""
    public var activeJobState: ProcessingJobState?
    /// Last user-visible error from import, transcription, or saving (cleared when a new run starts).
    public var importError: String?
    public var summaryText: String = ""
    public var chatReply: String = ""
    public var chatQuestion: String = ""
    /// Non-nil while the LLM is loading or generating (drives progress UI).
    public var llmWorkPhase: LLMWorkPhase?
    /// Rough online cost / usage line for the selected variant (online only).
    public var usageMeterText: String = ""
    /// Pipeline used for the in-flight transcription job (drives banner copy).
    public var activeTranscriptionMode: ProcessingMode?

    public var isTranscriptionBusy: Bool {
        guard let s = activeJobState else { return false }
        switch s {
        case .queued, .running, .paused:
            return true
        case .idle, .completed, .failed, .cancelled:
            return false
        }
    }

    private let repository: LibraryRepository
    public let processingQueue: ProcessingQueue
    private let export: ExportServicing
    private let offlineLLM: any LLMGenerating
    private let onlineLLM: any LLMGenerating
    public let userSettings = EchoDraftUserSettings.shared

    private let saveDebouncer = Debouncer()

    public init(
        repository: LibraryRepository,
        queue: ProcessingQueue,
        export: ExportServicing,
        offlineLLM: any LLMGenerating,
        onlineLLM: any LLMGenerating
    ) {
        self.repository = repository
        self.processingQueue = queue
        self.export = export
        self.offlineLLM = offlineLLM
        self.onlineLLM = onlineLLM
    }

    private func llmForCurrentSelection() throws -> any LLMGenerating {
        let mode = userSettings.effectiveMode(for: selectedRecording)
        if mode == .online {
            guard OpenAIAPIKeyStore.resolvedKey() != nil else {
                throw OpenAILLMError.noAPIKey
            }
            return onlineLLM
        }
        return offlineLLM
    }

    public func loadLibrary() throws {
        recordings = try repository.search(searchQuery)
        if selectedRecording == nil {
            selectedRecording = recordings.first
        }
        refreshUsageMeter()
    }

    public func refreshSearch() throws {
        recordings = try repository.search(searchQuery)
    }

    public func deleteRecording(_ recording: Recording) throws {
        try repository.delete(recording)
        if selectedRecording?.id == recording.id {
            selectedRecording = nil
        }
        try loadLibrary()
    }

    public func clearAllData() throws {
        try repository.clearEverything()
        recordings = []
        selectedRecording = nil
    }

    public func enqueueFiles(urls: [URL]) async throws {
        importError = nil
        let mode = userSettings.globalProcessingMode
        activeTranscriptionMode = mode
        if mode == .online {
            guard OpenAIAPIKeyStore.resolvedKey() != nil else {
                activeTranscriptionMode = nil
                importError =
                    "Online mode requires an OpenAI API key. Add one in Settings → Online (OpenAI) or switch to Offline."
                throw OpenAILLMError.noAPIKey
            }
        }
        for url in urls {
            _ = try await processingQueue.enqueue(url, mode: mode)
        }
    }

    /// Re-run transcription for the selected recording using the effective mode (creates a new variant).
    public func reprocessSelectedRecording() async throws {
        importError = nil
        guard let rec = selectedRecording, let url = rec.resolvedSourceURL() else {
            importError = "Could not resolve the original file for this recording."
            return
        }
        let mode = userSettings.effectiveMode(for: rec)
        activeTranscriptionMode = mode
        if mode == .online {
            guard OpenAIAPIKeyStore.resolvedKey() != nil else {
                activeTranscriptionMode = nil
                importError = "Online mode requires an OpenAI API key in Settings."
                throw OpenAILLMError.noAPIKey
            }
        }
        _ = try await processingQueue.enqueue(url, mode: mode, mergeIntoRecordingID: rec.id)
    }

    public func wireQueue() async {
        await processingQueue.setOnStateChange { [weak self] _, state in
            await MainActor.run {
                self?.activeJobState = state
                switch state {
                case .completed, .failed, .cancelled, .idle:
                    self?.activeTranscriptionMode = nil
                default:
                    break
                }
                if case .failed(let message) = state {
                    self?.importError = QueueErrorFormatting.humanize(message)
                    EchoDraftTelemetry.logOnlineFailure("queue: \(message)")
                }
            }
        }
        await processingQueue.setOnCompleted { [weak self] _, segments, sourceURL, _, mode, mergeId in
            await self?.persistCompleted(
                segments: segments,
                sourceURL: sourceURL,
                mode: mode,
                mergeIntoRecordingID: mergeId
            )
        }
    }

    private func persistCompleted(
        segments: [TimedTextSegment],
        sourceURL: URL,
        mode: ProcessingMode,
        mergeIntoRecordingID: UUID?
    ) async {
        await MainActor.run {
            let title = sourceURL.deletingPathExtension().lastPathComponent

            if let mergeId = mergeIntoRecordingID,
                let existing = self.recordings.first(where: { $0.id == mergeId })
            {
                self.appendVariantSync(
                    to: existing,
                    segments: segments,
                    sourceURL: sourceURL,
                    mode: mode
                )
                return
            }

            let newID = UUID()
            var order = 0
            var segs: [TranscriptSegment] = []
            for s in segments {
                let spk = s.speakerLabel ?? "Speaker \(s.speakerIndex + 1)"
                let seg = TranscriptSegment(
                    startSeconds: s.startSeconds,
                    endSeconds: s.endSeconds,
                    text: s.text,
                    speakerLabel: spk,
                    sortOrder: order
                )
                segs.append(seg)
                order += 1
            }

            let variant = TranscriptVariant(
                mode: mode,
                createdAt: Date(),
                usageJSON: self.usageJSON(for: mode, segments: segments)
            )
            let rec = Recording(
                id: newID,
                title: title,
                durationSeconds: segments.map(\.endSeconds).max() ?? 0,
                searchText: "",
                variants: [],
                activeVariantID: variant.id,
                processingModeOverrideRaw: nil
            )
            variant.recording = rec
            for seg in segs {
                seg.variant = variant
            }
            variant.segments = segs
            rec.variants = [variant]
            rec.recomputeSearchText()
            rec.sourceBookmarkData = try? sourceURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            do {
                try self.repository.insert(rec)
                try self.loadLibrary()
                self.selectedRecording = self.recordings.first(where: { $0.id == newID })
                self.importError = nil
            } catch {
                self.importError = "Could not save recording: \(error.localizedDescription)"
            }
        }
    }

    private func appendVariantSync(
        to recording: Recording,
        segments: [TimedTextSegment],
        sourceURL: URL,
        mode: ProcessingMode
    ) {
        var order = 0
        var segs: [TranscriptSegment] = []
        for s in segments {
            let spk = s.speakerLabel ?? "Speaker \(s.speakerIndex + 1)"
            let seg = TranscriptSegment(
                startSeconds: s.startSeconds,
                endSeconds: s.endSeconds,
                text: s.text,
                speakerLabel: spk,
                sortOrder: order
            )
            segs.append(seg)
            order += 1
        }
        let variant = TranscriptVariant(
            mode: mode,
            createdAt: Date(),
            usageJSON: usageJSON(for: mode, segments: segments)
        )
        variant.recording = recording
        for seg in segs {
            seg.variant = variant
        }
        variant.segments = segs
        recording.variants.append(variant)
        recording.activeVariantID = variant.id
        recording.durationSeconds = max(recording.durationSeconds, segments.map(\.endSeconds).max() ?? 0)
        recording.recomputeSearchText()
        if recording.sourceBookmarkData == nil {
            recording.sourceBookmarkData = try? sourceURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        do {
            try repository.save()
            try loadLibrary()
            selectedRecording = recordings.first(where: { $0.id == recording.id })
            importError = nil
            refreshUsageMeter()
        } catch {
            importError = "Could not save variant: \(error.localizedDescription)"
        }
    }

    private func usageJSON(for mode: ProcessingMode, segments: [TimedTextSegment]) -> String? {
        guard mode == .online else { return nil }
        let minutes = (segments.map(\.endSeconds).max() ?? 0) / 60.0
        // Rough gpt-4o family transcribe estimate ($0.006/min placeholder — informational only).
        let est = minutes * 0.006
        let dict: [String: Double] = ["audioMinutes": minutes, "estimatedTranscribeUSD": est]
        if let data = try? JSONEncoder().encode(dict),
            let s = String(data: data, encoding: .utf8)
        {
            return s
        }
        return nil
    }

    public func refreshUsageMeter() {
        guard let rec = selectedRecording,
            let vid = rec.activeVariantID,
            let v = rec.variants.first(where: { $0.id == vid }),
            v.processingMode == .online,
            let u = v.usageJSON,
            let data = u.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
            let min = obj["audioMinutes"],
            let usd = obj["estimatedTranscribeUSD"]
        else {
            usageMeterText = ""
            return
        }
        usageMeterText = String(format: "Online · ~%.1f min audio · ~$%.3f (transcribe est.)", min, usd)
    }

    public func exportMarkdown() -> String {
        guard let r = selectedRecording else { return "" }
        return export.markdown(for: r)
    }

    public func scheduleRecordingSave() {
        saveDebouncer.schedule { [weak self] in
            try? self?.saveSelectedRecordingNow()
        }
    }

    public func saveSelectedRecordingNow() throws {
        guard let r = selectedRecording else { return }
        r.recomputeSearchText()
        try repository.save()
    }

    public func exportPDFUsingSavePanel() throws {
        guard let r = selectedRecording else { return }
        let data = try export.pdfData(for: r)
        let base = sanitizeExportBasename(r.title)
        _ = try MacSavePanel.save(
            data: data,
            suggestedFilename: "\(base).pdf",
            allowedTypes: [.pdf]
        )
    }

    public func exportZIPUsingSavePanel() throws {
        guard let r = selectedRecording else { return }
        let audioURL = r.resolvedSourceURL()
        let zipTemp = try export.zipTranscriptAndAudio(recording: r, audioURL: audioURL)
        defer { try? FileManager.default.removeItem(at: zipTemp) }
        let base = sanitizeExportBasename(r.title)
        _ = try MacSavePanel.copyFile(
            from: zipTemp,
            suggestedFilename: "\(base).zip",
            allowedTypes: [.zip]
        )
    }

    public func runSummary(template: SummaryTemplate) async {
        guard let r = selectedRecording else { return }
        let text = r.activeSegmentsSorted().map(\.text).joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaryText =
                "No transcript text to summarize. Finish transcription or edit segments so they contain text."
            return
        }
        llmWorkPhase = .loadingModel(progress: 0)
        defer { llmWorkPhase = nil }
        do {
            let llm = try llmForCurrentSelection()
            try await llm.ensureLoaded { [weak self] p in
                Task { @MainActor in
                    self?.llmWorkPhase = .loadingModel(progress: p)
                }
            }
            llmWorkPhase = .summarizing
            summaryText = try await llm.summarize(transcript: text, template: template)
        } catch {
            summaryText = "Error: \(error.localizedDescription)"
            EchoDraftTelemetry.logOnlineFailure("summary: \(error.localizedDescription)")
        }
    }

    public func runChat() async {
        guard let r = selectedRecording else { return }
        let text = r.activeSegmentsSorted().map(\.text).joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatReply =
                "No transcript text yet. Finish transcription or add text to segments before asking a question."
            return
        }
        llmWorkPhase = .loadingModel(progress: 0)
        defer { llmWorkPhase = nil }
        do {
            let llm = try llmForCurrentSelection()
            try await llm.ensureLoaded { [weak self] p in
                Task { @MainActor in
                    self?.llmWorkPhase = .loadingModel(progress: p)
                }
            }
            llmWorkPhase = .chatting
            chatReply = try await llm.chat(transcript: text, question: chatQuestion)
        } catch {
            chatReply = "Error: \(error.localizedDescription)"
            EchoDraftTelemetry.logOnlineFailure("chat: \(error.localizedDescription)")
        }
    }
}

private func sanitizeExportBasename(_ s: String) -> String {
    s.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .prefix(80).description
}
