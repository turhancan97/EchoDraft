import AppKit
import SwiftData
import SwiftUI

public struct RootView: View {
    @Bindable public var viewModel: AppViewModel
    @State private var player = AudioPlaybackService()
    @State private var securityScopedURL: URL?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedRecording) {
                ForEach(viewModel.recordings, id: \.id) { rec in
                    Text(rec.title).tag(rec as Recording?)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button("Add files", systemImage: "plus") {
                        pickFiles()
                    }
                }
                ToolbarItem {
                    Button("Export PDF…", systemImage: "doc.richtext") {
                        try? viewModel.exportPDFUsingSavePanel()
                    }
                }
                ToolbarItem {
                    Button("Export ZIP…", systemImage: "archivebox") {
                        try? viewModel.exportZIPUsingSavePanel()
                    }
                }
                ToolbarItem {
                    Button("Clear library", systemImage: "trash") {
                        try? viewModel.clearAllData()
                    }
                }
            }
        } detail: {
            HSplitView {
                transcriptColumn
                    .frame(minWidth: 320)
                summaryColumn
                    .frame(minWidth: 280)
            }
        }
        .searchable(text: $viewModel.searchQuery)
        .onChange(of: viewModel.searchQuery) { _, _ in
            try? viewModel.refreshSearch()
        }
        .onChange(of: viewModel.selectedRecording?.id) { _, _ in
            Task { await reloadPlaybackForSelection() }
        }
        .task {
            await viewModel.wireQueue()
            try? viewModel.loadLibrary()
            await reloadPlaybackForSelection()
        }
    }

    private var transcriptColumn: some View {
        Group {
            if let rec = viewModel.selectedRecording {
                TranscriptDetailView(
                    recording: rec,
                    player: player,
                    onFieldEdited: { viewModel.scheduleRecordingSave() }
                )
                .padding()
            } else {
                ContentUnavailableView("No recording", systemImage: "waveform")
            }
        }
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary").font(.headline)
            HStack {
                Button("Bullets") {
                    Task { await viewModel.runSummary(template: .bulletPoints) }
                }
                Button("Executive") {
                    Task { await viewModel.runSummary(template: .executive) }
                }
                Button("Copy MD") {
                    let md = viewModel.exportMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                }
            }
            ScrollView {
                Text(viewModel.summaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Chat").font(.headline)
            TextField("Question", text: $viewModel.chatQuestion)
            Button("Ask") {
                Task { await viewModel.runChat() }
            }
            ScrollView {
                Text(viewModel.chatReply)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.audio, .movie, .mpeg4Audio, .mp3]
        if p.runModal() == .OK {
            Task {
                try? await viewModel.enqueueFiles(urls: p.urls)
            }
        }
    }

    private func reloadPlaybackForSelection() async {
        if let prev = securityScopedURL {
            prev.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
        guard let rec = viewModel.selectedRecording,
            let url = rec.resolvedSourceURL()
        else {
            return
        }
        let ok = url.startAccessingSecurityScopedResource()
        if ok {
            securityScopedURL = url
        }
        try? await player.load(url: url)
    }
}

private struct TranscriptDetailView: View {
    @Bindable var recording: Recording
    var player: AudioPlaybackService
    let onFieldEdited: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.title).font(.title2)
            List {
                ForEach(recording.segments.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { seg in
                    TranscriptSegmentRow(
                        segment: seg,
                        recording: recording,
                        player: player,
                        onFieldEdited: onFieldEdited
                    )
                }
            }
            HStack {
                Button("Play") { Task { await player.play() } }
                Button("Pause") { Task { await player.pause() } }
            }
        }
    }
}

private struct TranscriptSegmentRow: View {
    @Bindable var segment: TranscriptSegment
    @Bindable var recording: Recording
    var player: AudioPlaybackService
    let onFieldEdited: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Speaker", text: $segment.speakerLabel)
                .textFieldStyle(.roundedBorder)
                .onChange(of: segment.speakerLabel) { _, _ in
                    onFieldEdited()
                }
            TextField("Transcript", text: $segment.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onChange(of: segment.text) { _, _ in
                    recording.recomputeSearchText()
                    onFieldEdited()
                }
            Button(formatTime(segment.startSeconds)) {
                Task { await player.seek(to: segment.startSeconds) }
            }
            .buttonStyle(.link)
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds) % 60
        let m = Int(seconds) / 60
        return String(format: "%d:%02d", m, s)
    }
}
