import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct RootView: View {
    @Bindable public var viewModel: AppViewModel
    @State private var player = AudioPlaybackService()
    @State private var securityScopedURL: URL?
    @State private var showOnlinePrivacySheet = false
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
            .onChange(of: viewModel.selectedRecording?.id) { _, _ in
                viewModel.refreshUsageMeter()
            }
            .onChange(of: viewModel.userSettings.globalProcessingMode) { _, newValue in
                if newValue == .online, !viewModel.userSettings.onlinePrivacyAcknowledged {
                    showOnlinePrivacySheet = true
                }
            }
            .sheet(isPresented: $showOnlinePrivacySheet) {
                onlinePrivacySheet
            }
        }
    }

    private var onlinePrivacySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Online mode")
                .font(DesignSystem.headlineRounded())
            Text(
                "Audio is uploaded for transcription and text may be sent for summarization. You can switch back to Offline anytime."
            )
            .foregroundStyle(.secondary)
            Button("Continue") {
                viewModel.userSettings.onlinePrivacyAcknowledged = true
                showOnlinePrivacySheet = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(DesignSystem.outerPadding)
        .frame(minWidth: 380)
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
                Picker(
                    "Default mode",
                    selection: Binding(
                        get: { viewModel.userSettings.globalProcessingMode },
                        set: { viewModel.userSettings.globalProcessingMode = $0 }
                    )
                ) {
                    Text("Offline").tag(ProcessingMode.offline)
                    Text("Online").tag(ProcessingMode.online)
                }
                .frame(width: 100)
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
                    Text(progressCaption(for: p))
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
        case .running(let p) where p < 0.12:
            return "Preparing audio…"
        case .running(let p) where p < 0.52:
            if viewModel.activeTranscriptionMode == .online {
                return "Transcribing (OpenAI)…"
            }
            return "Transcribing (on-device)…"
        case .running(let p) where p < 0.88:
            if viewModel.activeTranscriptionMode == .offline {
                return "Diarizing speakers…"
            }
            return "Finishing…"
        case .running:
            return "Finishing…"
        case .paused:
            return "Paused"
        default:
            return "Processing…"
        }
    }

    private func progressCaption(for p: Double) -> String {
        if viewModel.activeTranscriptionMode == .online {
            return "Progress \(Int(p * 100))% — uploading and transcribing via your API endpoint."
        }
        return "Progress \(Int(p * 100))% — first run may download large models."
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

    private var loadingModelTitle: String {
        if viewModel.userSettings.effectiveMode(for: viewModel.selectedRecording) == .online {
            return "Preparing online model"
        }
        return "Loading language model"
    }

    private func loadingModelCaption(_ p: Double) -> String {
        if viewModel.userSettings.effectiveMode(for: viewModel.selectedRecording) == .online {
            return "\(Int((p * 100).rounded()))% — connecting to the API."
        }
        return "\(Int((p * 100).rounded()))% — first run may download a large checkpoint."
    }

    private var transcriptColumn: some View {
        Group {
            if let rec = viewModel.selectedRecording {
                TranscriptDetailView(
                    recording: rec,
                    viewModel: viewModel,
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
            if !viewModel.usageMeterText.isEmpty {
                Text(viewModel.usageMeterText)
                    .font(DesignSystem.captionMuted())
                    .foregroundStyle(.secondary)
            }
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
                    Text(loadingModelTitle)
                        .font(DesignSystem.headlineRounded())
                    ProgressView(value: p, total: 1)
                        .tint(DesignSystem.accentElectricBlue)
                    Text(loadingModelCaption(p))
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
    var viewModel: AppViewModel
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

            HStack(spacing: 12) {
                Text("Transcribe as")
                    .font(DesignSystem.captionMuted())
                    .foregroundStyle(.secondary)
                Picker(
                    "",
                    selection: Binding(
                        get: {
                            if let r = recording.processingModeOverrideRaw,
                                let m = ProcessingMode(rawValue: r)
                            {
                                switch m {
                                case .offline: return 1
                                case .online: return 2
                                }
                            }
                            return 0
                        },
                        set: { idx in
                            switch idx {
                            case 0: recording.processingModeOverrideRaw = nil
                            case 1: recording.processingModeOverrideRaw = ProcessingMode.offline.rawValue
                            case 2: recording.processingModeOverrideRaw = ProcessingMode.online.rawValue
                            default: break
                            }
                            onFieldEdited()
                        }
                    )
                ) {
                    Text("App default").tag(0)
                    Text("Offline").tag(1)
                    Text("Online").tag(2)
                }
                .labelsHidden()
                .frame(width: 140)
            }

            if recording.variants.count > 1 {
                Picker(
                    "Transcript version",
                    selection: Binding(
                        get: { recording.activeVariantID ?? recording.variants.first?.id },
                        set: { newId in
                            recording.activeVariantID = newId
                            onFieldEdited()
                            viewModel.refreshUsageMeter()
                        }
                    )
                ) {
                    ForEach(recording.variants.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { v in
                        Text(variantMenuLabel(v)).tag(Optional(v.id))
                    }
                }
            }

            List {
                ForEach(recording.activeSegmentsSorted(), id: \.id) { seg in
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
                Button("Re-transcribe") {
                    Task {
                        do {
                            try await viewModel.reprocessSelectedRecording()
                        } catch {
                            viewModel.importError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(EchoBorderedButtonStyle(prominent: false))
                .disabled(viewModel.isTranscriptionBusy)
            }
        }
    }

    private func variantMenuLabel(_ v: TranscriptVariant) -> String {
        let m = v.processingMode.displayName
        let t = v.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(m) · \(t)"
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
