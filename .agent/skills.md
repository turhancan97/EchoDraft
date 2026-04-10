# EchoDraft: Technical Stack & Required Skills

## Target Environment
* **OS:** macOS 14.0 (Sonoma) and later.
* **Architecture:** Apple Silicon (ARM64) optimized.
* **Language:** Swift 5.10+

## Core Frameworks
1.  **UI:** SwiftUI exclusively. Do not use AppKit (`NSViewController`, `NSWindow`) unless absolutely necessary for specific macOS integrations (like the persistent Menu Bar icon). 
    * Use `@Observable` macro for state management (macOS 14 standard).
2.  **Machine Learning:** Apple MLX (`mlx-swift`). 
    * Use MLX for Whisper (speech-to-text) and local LLM inference (summarization/chat/name resolution).
    * Do *not* use CoreML or external cloud APIs (OpenAI, etc.).
3.  **Audio & Video:** `AVFoundation`.
    * Use `AVAudioEngine` or `AVPlayer` for playback.
    * Use `AVAssetReader` for extracting audio tracks from video files (MP4, MOV).
4.  **Database:** `SwiftData`.
    * Use SwiftData for the local library (storing transcripts, timestamps, summaries, and speaker metadata).
5.  **Testing:** `XCTest`.
    * Write robust unit tests for all business logic.
    * Mock dependencies (e.g., `MockAudioPlayer`, `MockLLMRunner`) to test ViewModels in isolation.

## Specific Implementations
* **Menu Bar Icon:** Use `MenuBarExtra` in the main `App` struct.
* **Export:** * PDF: Use `ImageRenderer` or `PDFKit`.
    * Markdown: Native String manipulation.
    * Apple Notes: Use `NSSharingService` or AppleScript bridging.
* **Sandboxing:** App entitlements must reflect a strict local environment.