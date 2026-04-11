import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct RootView: View {
    @Bindable public var viewModel: AppViewModel
    @State private var player = AudioPlaybackService()
    @State private var securityScopedURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            processingStatusBanner
            NavigationSplitView {
                librarySidebar
            } detail: {
                HSplitView {
                    transcriptColumn
                        .frame(minWidth: 320)
                    summaryColumn
                        .frame(minWidth: 280)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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
    }

    private var librarySidebar: some View {
        List(selection: $viewModel.selectedRecording) {
            ForEach(viewModel.recordings, id: \.id) { rec in
                Text(rec.title)
                    .tag(rec as Recording?)
                    .padding(.vertical, 4)
                    .echoHoverScale()
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .echoFrostedPanel()
        .toolbar {
            ToolbarItemGroup {
                toolbarChromeButton(systemName: "plus", help: "Add files", action: pickFiles)
                toolbarChromeButton(systemName: "doc.richtext", help: "Export PDF…") {
                    try? viewModel.exportPDFUsingSavePanel()
                }
                toolbarChromeButton(systemName: "archivebox", help: "Export ZIP…") {
                    try? viewModel.exportZIPUsingSavePanel()
                }
                toolbarChromeButton(systemName: "trash", help: "Clear library") {
                    try? viewModel.clearAllData()
                }
            }
        }
    }

    private func toolbarChromeButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            EchoGradientSymbolIcon(systemName: systemName, size: 16)
                .padding(6)
        }
        .buttonStyle(EchoBorderedButtonStyle(prominent: false))
        .help(help)
    }

    @ViewBuilder
    private var processingStatusBanner: some View {
        if let err = viewModel.importError, !err.isEmpty {
            HStack(alignment: .top, spacing: DesignSystem.sectionSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.3), radius: 2, y: 1)
                Text(err)
                    .font(DesignSystem.bodyReadable())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(EchoBannerModifier(isError: true))
            .padding(.horizontal, DesignSystem.outerPadding)
            .padding(.top, DesignSystem.sectionSpacing)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(
                DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: viewModel.importError ?? ""),
                value: viewModel.importError
            )
        }
        if showsActiveProcessing {
            VStack(alignment: .leading, spacing: 8) {
                Text(processingTitle)
                    .font(DesignSystem.headlineRounded())
                    .foregroundStyle(.primary)
                if case .running(let p) = viewModel.activeJobState {
                    ProgressView(value: p, total: 1)
                        .tint(DesignSystem.accentElectricBlue)
                    Text("Progress \(Int(p * 100))% — first run may download large models.")
                        .font(DesignSystem.captionMuted())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                } else {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(DesignSystem.accentElectricBlue)
                    Text(processingSubtitle)
                        .font(DesignSystem.captionMuted())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
            .modifier(EchoBannerModifier(isError: false))
            .padding(.horizontal, DesignSystem.outerPadding)
            .padding(.vertical, DesignSystem.sectionSpacing)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(
                DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: viewModel.activeJobState),
                value: viewModel.activeJobState
            )
        }
    }

    private var showsActiveProcessing: Bool {
        guard let s = viewModel.activeJobState else { return false }
        switch s {
        case .running, .paused, .queued:
            return true
        default:
            return false
        }
    }

    private var processingTitle: String {
        guard let s = viewModel.activeJobState else { return "Processing" }
        switch s {
        case .queued:
            return "Queued…"
        case .running(let p) where p < 0.25:
            return "Preparing audio…"
        case .running(let p) where p < 0.75:
            return "Transcribing (MLX)…"
        case .running:
            return "Finishing…"
        case .paused:
            return "Paused"
        default:
            return "Processing…"
        }
    }

    private var processingSubtitle: String {
        guard let s = viewModel.activeJobState else { return "" }
        switch s {
        case .paused:
            return "Resume from the queue when supported."
        default:
            return ""
        }
    }

    private var transcriptColumn: some View {
        Group {
            if let rec = viewModel.selectedRecording {
                TranscriptDetailView(
                    recording: rec,
                    player: player,
                    onFieldEdited: { viewModel.scheduleRecordingSave() },
                    colorScheme: colorScheme
                )
            } else {
                ContentUnavailableView {
                    Label("No recording", systemImage: "waveform")
                } description: {
                    Text("Add files from the toolbar to get started.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .echoFrostedPanel()
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: DesignSystem.sectionSpacing) {
            Text("Summary")
                .font(DesignSystem.headlineRounded())
                .foregroundStyle(.primary)
            llmProgressSection
            HStack(spacing: 10) {
                Button("Bullets") {
                    Task { await viewModel.runSummary(template: .bulletPoints) }
                }
                .buttonStyle(EchoBorderedButtonStyle(prominent: true))
                .disabled(viewModel.llmWorkPhase != nil)

                Button("Executive") {
                    Task { await viewModel.runSummary(template: .executive) }
                }
                .buttonStyle(EchoBorderedButtonStyle(prominent: true))
                .disabled(viewModel.llmWorkPhase != nil)

                Button("Copy MD") {
                    let md = viewModel.exportMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                }
                .buttonStyle(EchoBorderedButtonStyle(prominent: false))
            }
            ScrollView {
                Text(viewModel.summaryText)
                    .font(DesignSystem.bodyReadable())
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
                .opacity(0.35)
            Text("Chat")
                .font(DesignSystem.headlineRounded())
            TextField("Question", text: $viewModel.chatQuestion)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.llmWorkPhase != nil)
            Button("Ask") {
                Task { await viewModel.runChat() }
            }
            .buttonStyle(EchoBorderedButtonStyle(prominent: true))
            .disabled(viewModel.llmWorkPhase != nil)
            ScrollView {
                Text(viewModel.chatReply)
                    .font(DesignSystem.bodyReadable())
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .echoFrostedPanel()
    }

    @ViewBuilder
    private var llmProgressSection: some View {
        if let phase = viewModel.llmWorkPhase {
            VStack(alignment: .leading, spacing: 8) {
                switch phase {
                case .loadingModel(let p):
                    Text("Loading language model")
                        .font(DesignSystem.headlineRounded())
                    ProgressView(value: p, total: 1)
                        .tint(DesignSystem.accentElectricBlue)
                    Text("\(Int((p * 100).rounded()))% — first run may download a large checkpoint.")
                        .font(DesignSystem.captionMuted())
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                case .summarizing:
                    Text("Writing summary…")
                        .font(DesignSystem.headlineRounded())
                    ProgressView()
                        .controlSize(.small)
                        .tint(DesignSystem.accentElectricBlue)
                case .chatting:
                    Text("Generating answer…")
                        .font(DesignSystem.headlineRounded())
                    ProgressView()
                        .controlSize(.small)
                        .tint(DesignSystem.accentElectricBlue)
                }
            }
            .padding(DesignSystem.listRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius, style: .continuous)
                            .strokeBorder(DesignSystem.accentElectricBlue.opacity(0.35), lineWidth: 1)
                    }
            }
            .animation(
                DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: phase),
                value: phase
            )
        }
    }

    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .mpeg4Audio, .mp3]
        if p.runModal() == .OK {
            Task {
                do {
                    try await viewModel.enqueueFiles(urls: p.urls)
                } catch {
                    viewModel.importError = error.localizedDescription
                }
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
    var colorScheme: ColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.sectionSpacing) {
            Text(recording.title)
                .font(DesignSystem.titleRounded())
                .foregroundStyle(.primary)
                .animation(
                    DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: recording.title),
                    value: recording.title
                )
            List {
                ForEach(recording.segments.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { seg in
                    TranscriptSegmentRow(
                        segment: seg,
                        recording: recording,
                        player: player,
                        onFieldEdited: onFieldEdited,
                        colorScheme: colorScheme
                    )
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            HStack(spacing: 12) {
                Button("Play") { Task { await player.play() } }
                    .buttonStyle(EchoBorderedButtonStyle(prominent: true))
                Button("Pause") { Task { await player.pause() } }
                    .buttonStyle(EchoBorderedButtonStyle(prominent: false))
            }
        }
    }
}

private struct TranscriptSegmentRow: View {
    @Bindable var segment: TranscriptSegment
    @Bindable var recording: Recording
    var player: AudioPlaybackService
    let onFieldEdited: () -> Void
    var colorScheme: ColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.sectionSpacing) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DesignSystem.speakerStripeColor(for: segment.speakerLabel))
                .frame(width: DesignSystem.stripeWidth)
                .padding(.vertical, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Speaker", text: $segment.speakerLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.bodyReadable())
                    .onChange(of: segment.speakerLabel) { _, _ in
                        onFieldEdited()
                    }
                TextField("Transcript", text: $segment.text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.bodyReadable())
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .onChange(of: segment.text) { _, _ in
                        recording.recomputeSearchText()
                        onFieldEdited()
                    }
                Button(formatTime(segment.startSeconds)) {
                    Task { await player.seek(to: segment.startSeconds) }
                }
                .buttonStyle(EchoTimestampButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.listRowPadding)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.speakerRowTint(for: segment.speakerLabel, colorScheme: colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        }
        .echoHoverScale()
        .animation(
            DesignSystem.preferredAnimation(reduceMotion: reduceMotion, value: segment.id),
            value: segment.text
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds) % 60
        let m = Int(seconds) / 60
        return String(format: "%d:%02d", m, s)
    }
}
