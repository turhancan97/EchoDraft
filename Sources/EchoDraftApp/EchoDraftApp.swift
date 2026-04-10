import AppKit
import EchoDraftCore
import SwiftUI

@main
struct EchoDraftApp: App {
    @NSApplicationDelegateAdaptor(EchoDraftAppDelegate.self) private var appDelegate
    @State private var viewModel: AppViewModel

    init() {
        let repo = FileLibraryRepository()
        let queue = ProcessingQueue(
            extract: AudioExtractionService(),
            transcribe: StubTranscriptionService(),
            diarize: PauseBasedDiarizationService()
        )
        _viewModel = State(
            initialValue: AppViewModel(
                repository: repo,
                queue: queue,
                export: ExportService(),
                llm: StubLLMService()
            ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("EchoDraft", systemImage: "waveform") {
            Button("Open EchoDraft") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
