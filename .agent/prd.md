# EchoDraft: Product Requirements Document (PRD)

## 1. Product Identity & Branding
EchoDraft is a professional, accessible, and developer-friendly macOS application. 

* **Core Values:** 100% Privacy (Air-gapped), Open-Source, macOS Native, Zero-Cost.
* **Target Platform:** macOS 14 Sonoma and later (Apple Silicon highly recommended).
* **Visual Language:**
    * **Theme:** Native SwiftUI, supporting both Light and Dark modes seamlessly.
    * **Layout:** Clean, 3-pane architecture (Sidebar for Library, Main area for Transcript, Right-panel for Summary/Chat).
    * **Color Palette:** Standard macOS system colors to ensure it feels like a first-party Apple app. Minimalist grays with subtle system blues for primary actions.
    * **Iconography:** Apple SF Symbols exclusively.
    * **Menu Bar:** A persistent, minimalist Menu Bar icon providing background status and quick access.

---

## 2. Core Feature List

### Input & File Management
* **Media Support:** Drag-and-drop or file picker for audio (MP3, WAV, M4A) and video (MP4, MOV with automatic background audio extraction).
* **Bulk Queueing:** Add multiple files to a processing queue.
* **Limits & Controls:** Configurable file size/length limits to prevent memory crashes. Pause, resume, and cancel functionality for active processing.
* **Future-proofing:** UI and service hooks designed to easily adopt live microphone recording in future updates.

### Playback & Review
* **Integrated Player:** Built-in AVFoundation audio playback controls synced perfectly with the transcribed text.
* **Clickable Timestamps:** Clicking any timestamp in the transcript jumps the audio player to that exact millisecond.
* **Manual Editing:** A fully editable transcript view allowing users to correct AI transcription mistakes or adjust speaker names.

### AI Processing (Transcription & Diarization)
* **Local Engine:** High-accuracy, offline speech-to-text utilizing Apple's MLX framework.
* **Speaker Diarization:** Automatic detection of distinct voices, natively tagged as "Speaker 1", "Speaker 2", etc.
* **Smart Name Resolution:** A secondary local LLM pass to map conversational names to speaker tags. The UI will subtly highlight uncertain name guesses for user verification.
* **Multi-Language:** Model support for non-English transcription and summarization.

### Summarization & RAG (Retrieval-Augmented Generation)
* **Smart Titling:** Auto-generates concise meeting titles based on the transcript's content.
* **Template Summaries:** User-selectable output formats (e.g., "Action Items," "Executive Summary," "Bullet Points").
* **Chat with Transcript:** A conversational interface allowing the user to ask the local LLM specific questions regarding the meeting content.

### Data, Privacy & Export
* **On-Demand Models:** Whisper and LLM models are downloaded only on the first launch. Afterward, the app operates in a strict offline sandbox.
* **Local Library & Search:** A persistent SwiftData history tab with global search across all past transcripts.
* **Storage Optimization:** Option to automatically delete original audio files post-processing to save disk space.
* **Nuclear Option:** A prominent "Clear All Data" feature to instantly wipe all databases, transcripts, and model caches.
* **Rich Export:** 1-click export functionality to Apple Notes, PDF, Markdown, or a packaged `.zip`/folder containing both text and audio.

---

## 3. Standard User Flow
1. **Onboarding:** User launches the app. The UI prompts the initial download of the required MLX Whisper and LLM models. The app then enters offline-sandbox mode.
2. **Ingestion:** User drags media into the main window or uses the Menu Bar icon. If video, the app extracts audio, checks constraints, and adds the file to the queue.
3. **Processing:** The app processes the audio locally, displaying a pausable/cancellable progress indicator.
4. **Review:** The transcript is displayed with highlighted names for verification. The user can play audio natively and click timestamps to navigate.
5. **Interact:** The user can select a summary template or use the "Chat" tab to query the transcript using the local LLM.
6. **Manage & Export:** The processed file is saved to the local SwiftData Library. The user can globally search past entries or export the current session to Apple Notes, PDF, or Markdown.

---

## 4. Architecture & Non-Functional Requirements
* **Architecture:** Strict MVVM (Model-View-ViewModel).
    * **Views** handle solely UI rendering and user interaction bindings.
    * **ViewModels** manage application state and presentation logic.
    * **Services** (Audio, AI, Storage) handle domain logic and must be protocol-oriented for dependency injection.
* **Testing:** Strict Test-Driven Development (TDD). The agent must write and verify XCTest unit tests for all ViewModels, utility functions, and Services *before* generating the SwiftUI Views.
* **Performance:** Heavy operations (audio processing, ML inference) must be offloaded from the main thread using Swift Concurrency (`async/await`, `Task`, `actor`) to ensure zero UI freezing.
* **Modularity:** Models, Views, ViewModels, and Services must reside in strictly separated directories.