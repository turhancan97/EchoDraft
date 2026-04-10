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
    public var summaryText: String = ""
    public var chatReply: String = ""
    public var chatQuestion: String = ""

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
        for url in urls {
            _ = try await processingQueue.enqueue(url)
        }
    }

    public func wireQueue() async {
        await processingQueue.setOnStateChange { [weak self] _, state in
            await MainActor.run {
                self?.activeJobState = state
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
        } catch {}
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
        do {
            try await llm.ensureLoaded { _ in }
            summaryText = try await llm.summarize(transcript: text, template: template)
        } catch {
            summaryText = "Error: \(error.localizedDescription)"
        }
    }

    public func runChat() async {
        guard let r = selectedRecording else { return }
        let text = r.segments.sorted { $0.sortOrder < $1.sortOrder }.map(\.text).joined(separator: "\n")
        do {
            try await llm.ensureLoaded { _ in }
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
