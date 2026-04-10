---
name: echodraft
description: Defines architecture, product scope, and TDD workflow for EchoDraft, an offline macOS 14+ SwiftUI app using MLX, AVFoundation, and SwiftData. Use when working in this repository, implementing PRD features, or when the user mentions EchoDraft, MLX, local Whisper, diarization, or SwiftData transcription libraries.
---

# EchoDraft (macOS)

## Product

EchoDraft is a privacy-first, air-gapped, native macOS app: local transcription (Whisper via MLX), speaker diarization, summaries and chat over transcripts, library/search, and export—no cloud inference in core logic. Target: **macOS 14+**, **Apple Silicon** assumed.

## Non-negotiables

1. **TDD order:** Write **XCTest** for ViewModels, Services, and Utilities **before** production code; tests pass **before** building SwiftUI Views.
2. **MVVM:** Views = UI + bindings only. ViewModels = presentation state + bridge to Services. Services = domain work; define **protocols** for injection and mocks (`MockAudioPlayer`, `MockLLMRunner`, etc.).
3. **Privacy:** **No network calls** in core app logic. Networking is **only** for **initial MLX model download**; then strict offline sandbox.
4. **Concurrency:** Audio decode, ML, and heavy I/O off the main thread (`async`/`await`, `Task`, `actor`); keep UI fluid.
5. **Scope:** Do not rewrite files outside the current task’s scope (e.g. Audio Service work does not mean editing unrelated Views).

## Tech stack

| Area | Choice |
|------|--------|
| UI | SwiftUI; `@Observable` for state (macOS 14). AppKit only when required (e.g. integrations). **Menu bar:** `MenuBarExtra`. |
| ML | **mlx-swift** — Whisper STT, local LLM for summaries, chat, name resolution. **No** CoreML for this pipeline; **no** OpenAI/cloud APIs for inference. |
| AV | **AVFoundation** — `AVPlayer` / `AVAudioEngine` playback; **AVAssetReader** (or equivalent) for audio from MP4/MOV. |
| Data | **SwiftData** — library, transcripts, timestamps, summaries, speaker metadata. |
| Tests | **XCTest**; mock service protocols in ViewModel tests. |

## UX and visual rules

- **Layout:** Three panes — library sidebar, main transcript, right panel (summary/chat).
- **Look:** System colors, light/dark; **SF Symbols** only; minimalist, first-party feel.
- **Playback:** Player synced to transcript; **clickable timestamps**; transcript and speaker labels **editable**.

## Feature domains (implementation hooks)

- **Ingest:** Drag/drop + picker; audio MP3/WAV/M4A; video MP4/MOV with background audio extract; **queue** with pause/resume/cancel; configurable size/duration limits.
- **AI:** Offline STT + diarization (Speaker 1, 2, …); LLM pass for **name → speaker** mapping (uncertain guesses surfaced in UI); multi-language models where applicable.
- **Output:** Template summaries (action items, executive, bullets); **chat with transcript**; smart titles.
- **Data lifecycle:** Optional delete source audio after processing; global search; **Clear All Data**; export to Notes, PDF, Markdown, zip/folder with text + audio.

## Coding style

- Swift naming conventions; prefer `struct` unless reference semantics or `@Observable` / service lifetime needs a `class`.
- Small, single-purpose functions; **throw** or typed errors with **clear user-facing messages** for corrupt media, OOM, etc.

## Authoritative docs in repo

- Full PRD, agent rules, and stack notes: see [reference.md](reference.md).
