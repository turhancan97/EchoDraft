# EchoDraft

Offline-first macOS app for local transcription, diarization, summaries, and chat over your recordings. See [.agent/prd.md](.agent/prd.md) and [.agent/first-release-v1.md](.agent/first-release-v1.md).

## Project layout

```text
EchoDraft/
├── Package.swift              # Swift Package: EchoDraftCore library + EchoDraft executable
├── Sources/
│   ├── EchoDraftCore/         # Models, services, view models, SwiftUI views
│   └── EchoDraftApp/          # @main app entry, menu bar extra
├── .github/workflows/ci.yml
└── .agent/                    # PRD and agent docs
```

## Build

Requirements: **macOS 14+**, **Apple Silicon**, Swift 6 / Xcode 15+ recommended.

```bash
swift build
swift run EchoDraft
```

`swift run` **blocks the terminal** while the app is open—that is normal. You should see an **EchoDraft** icon in the **Dock**, a **window**, and a **menu bar extra** (waveform). If nothing appears, try **Terminal.app** (not an IDE-embedded terminal), or press **Cmd+Tab** to focus EchoDraft. Opening `Package.swift` in **Xcode** and running the **EchoDraft** scheme is the most reliable way to debug the GUI.

## Implementation notes (v1 scaffold)

- **Library:** JSON file in Application Support (`FileLibraryRepository`). The PRD targets SwiftData; migrating to `@Model` in an Xcode app target is straightforward once you enable SwiftData macros in that target.
- **Transcription:** `StubTranscriptionService` for fast builds/CI. Swap for MLX/Whisper (e.g. mlx-swift + community STT) behind `TranscriptionServicing`.
- **LLM:** `StubLLMService` implements `LLMGenerating`. Replace with **mlx-swift-lm** (`LLMModelFactory` / `ChatSession`) when you add MLX packages back to `Package.swift`.
- **Exports:** Markdown, PDF (via `NSTextView`), ZIP (`ZIPFoundation`), Notes (sharing services with pasteboard fallback).

## CI

GitHub Actions runs `swift build` on `macos-14`. Add `swift test` after reintroducing a test target (XCTest or swift-testing with full Xcode).

## Release

Sign with **Developer ID**, **notarize**, distribute via **GitHub Releases** (see [.agent/first-release-v1.md](.agent/first-release-v1.md) §6).
