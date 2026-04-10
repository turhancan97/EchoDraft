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

    private let repository: LibraryRepository
    public let processingQueue: ProcessingQueue
    private let export: ExportServicing
    private let llm: any LLMGenerating

    private let saveDebouncer = Debouncer()

    public init(
        repository: LibraryRepository,
        queue: ProcessingQueue,
        export: ExportServicing,
        llm: any LLMGenerating
    ) {
        self.repository = repository
        self.processingQueue = queue
        self.export = export
        self.llm = llm
    }

    public func loadLibrary() throws {
        recordings = try repository.search(searchQuery)
        if selectedRecording == nil {
            selectedRecording = recordings.first
        }
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
        for url in urls {
            _ = try await processingQueue.enqueue(url)
        }
    }

    public func wireQueue() async {
        await processingQueue.setOnStateChange { [weak self] _, state in
            await MainActor.run {
                self?.activeJobState = state
                if case .failed(let message) = state {
                    self?.importError = message
                }
            }
        }
        await processingQueue.setOnCompleted { [weak self] _, segments, sourceURL, _ in
            await self?.persistCompleted(segments: segments, sourceURL: sourceURL)
        }
    }

    private func persistCompleted(segments: [TimedTextSegment], sourceURL: URL) async {
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let newID = UUID()
        var order = 0
        var segs: [TranscriptSegment] = []
        for s in segments {
            let spk = "Speaker \(s.speakerIndex + 1)"
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
        let rec = Recording(
            id: newID,
            title: title,
            durationSeconds: segments.map(\.endSeconds).max() ?? 0,
            searchText: "",
            segments: []
        )
        for seg in segs {
            seg.recording = rec
        }
        rec.segments = segs
        rec.recomputeSearchText()
        rec.sourceBookmarkData = try? sourceURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        do {
            try repository.insert(rec)
            try loadLibrary()
            selectedRecording = recordings.first(where: { $0.id == newID })
            importError = nil
        } catch {
            importError = "Could not save recording: \(error.localizedDescription)"
        }
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
        let text = r.segments.sorted { $0.sortOrder < $1.sortOrder }.map(\.text).joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaryText =
                "No transcript text to summarize. Finish transcription or edit segments so they contain text."
            return
        }
        llmWorkPhase = .loadingModel(progress: 0)
        defer { llmWorkPhase = nil }
        do {
            try await llm.ensureLoaded { [weak self] p in
                Task { @MainActor in
                    self?.llmWorkPhase = .loadingModel(progress: p)
                }
            }
            llmWorkPhase = .summarizing
            summaryText = try await llm.summarize(transcript: text, template: template)
        } catch {
            summaryText = "Error: \(error.localizedDescription)"
        }
    }

    public func runChat() async {
        guard let r = selectedRecording else { return }
        let text = r.segments.sorted { $0.sortOrder < $1.sortOrder }.map(\.text).joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatReply =
                "No transcript text yet. Finish transcription or add text to segments before asking a question."
            return
        }
        llmWorkPhase = .loadingModel(progress: 0)
        defer { llmWorkPhase = nil }
        do {
            try await llm.ensureLoaded { [weak self] p in
                Task { @MainActor in
                    self?.llmWorkPhase = .loadingModel(progress: p)
                }
            }
            llmWorkPhase = .chatting
            chatReply = try await llm.chat(transcript: text, question: chatQuestion)
        } catch {
            chatReply = "Error: \(error.localizedDescription)"
        }
    }
}

private func sanitizeExportBasename(_ s: String) -> String {
    s.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .prefix(80).description
}
