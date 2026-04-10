import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct RootView: View {
    @Bindable public var viewModel: AppViewModel
    @State private var player = AudioPlaybackService()

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
        .task {
            await viewModel.wireQueue()
            try? viewModel.loadLibrary()
        }
    }

    private var transcriptColumn: some View {
        Group {
            if let rec = viewModel.selectedRecording {
                VStack(alignment: .leading) {
                    Text(rec.title).font(.title2)
                    List {
                        ForEach(Array(rec.segments.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated()), id: \.offset) { _, seg in
                            VStack(alignment: .leading) {
                                Text(seg.speakerLabel).font(.caption).foregroundStyle(.secondary)
                                Text(seg.text)
                                Button(formatTime(seg.startSeconds)) {
                                    Task { await player.seek(to: seg.startSeconds) }
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    HStack {
                        Button("Play") { Task { await player.play() } }
                        Button("Pause") { Task { await player.pause() } }
                    }
                }
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

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds) % 60
        let m = Int(seconds) / 60
        return String(format: "%d:%02d", m, s)
    }
}
