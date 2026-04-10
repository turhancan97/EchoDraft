import AppKit
import EchoDraftCore
import SwiftData
import SwiftUI

@main
@MainActor
struct EchoDraftApp: App {
    @NSApplicationDelegateAdaptor(EchoDraftAppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var viewModel: AppViewModel

    init() {
        do {
            container = try ModelContainer(for: Recording.self, TranscriptSegment.self)
        } catch {
            fatalError("Could not open SwiftData store: \(error.localizedDescription)")
        }
        let ctx = ModelContext(container)
        do {
            try JSONLibraryMigrator().migrateIfNeeded(modelContext: ctx)
        } catch {
            // Migration failure leaves JSON in place; app can still run on an empty store.
        }
        let repo = SwiftDataLibraryRepository(modelContext: ctx)
        let queue = ProcessingQueue(
            extract: AudioExtractionService(),
            transcribe: EchoDraftServiceFactory.makeTranscriptionService(),
            diarize: PauseBasedDiarizationService()
        )
        _viewModel = State(
            initialValue: AppViewModel(
                repository: repo,
                queue: queue,
                export: ExportService(),
                llm: EchoDraftServiceFactory.makeLLMService()
            ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .modelContainer(container)
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
