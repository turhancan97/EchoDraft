# EchoDraft — First release (v1) plan

This document implements the planning process from the EchoDraft v1 release questionnaire. **You did not supply Yes/No answers in chat**; the table below records **assumed answers** aligned with [.agent/prd.md](prd.md) and [.agent/agent.md](agent.md), with pragmatic cuts where noted. Replace any assumption by editing this file.

## 1. Questionnaire — assumed responses

| # | Question | Assumed | Notes |
|---|----------|---------|-------|
| 1 | macOS 14+ only for v1 | **Yes** | Matches PRD/agent. |
| 2 | Apple Silicon only for v1 | **Yes** | Matches PRD (highly recommended) and agent. |
| 3 | English-first for v1 | **Yes** | Multi-language per PRD → **Later** (model selection UX + QA). |
| 4 | Primary distribution outside Mac App Store for v1 | **Yes** | GitHub Releases + notarized ZIP/DMG. |
| 5 | Mac App Store submission is a v1 goal | **No** | Defer to reduce review/sandbox friction; see §2. |
| 6 | Drag-and-drop required in v1 | **Yes** | PRD. |
| 7 | Multi-file queue required in v1 | **Yes** | PRD. |
| 8 | Video (MP4/MOV) with audio extraction required in v1 | **Yes** | PRD. |
| 9 | Pause, resume, cancel required in v1 | **Yes** | PRD. |
| 10 | Speaker diarization required in v1 | **Yes** | PRD; high engineering risk — see §4. |
| 11 | At least one LLM summary template required in v1 | **Yes** | PRD. |
| 12 | Chat with transcript required in v1 | **Yes** | PRD. |
| 13 | Smart name resolution **deferred** past v1 | **Yes** | **Pragmatic cut:** defer “LLM maps names to speakers + uncertain highlights” to v1.1; v1 keeps Speaker 1/2 labels and manual rename. |
| 14 | Three-pane layout required in v1 | **Yes** | PRD. |
| 15 | Menu bar extra required in v1 | **Yes** | PRD. |
| 16 | SwiftData library persistence required in v1 | **Yes** | PRD / skill. |
| 17 | Global search across transcripts required in v1 | **Yes** | PRD. |
| 18 | “Clear all data” required in v1 | **Yes** | PRD. |
| 19 | Optional auto-delete source audio required in v1 | **No** | Ship as **stretch** if time; else v1.1. PRD lists as option. |
| 20 | Markdown export required in v1 | **Yes** | PRD. |
| 21 | PDF export required in v1 | **Yes** | PRD. |
| 22 | Apple Notes export required in v1 | **Yes** | PRD; **risk** — see §2 (sandbox). |
| 23 | Zip/folder export (text + audio) required in v1 | **Yes** | PRD. |
| 24 | First-launch download of MLX models (then offline) | **Yes** | PRD; only sanctioned network use per agent. |
| 25 | Bundled or user-supplied model paths in v1 | **Yes** | Advanced settings for power users / CI; default path remains download. |
| 26 | Integrated player synced with transcript required in v1 | **Yes** | PRD. |
| 27 | Clickable timestamps (seek) required in v1 | **Yes** | PRD. |
| 28 | Fully editable transcript + speaker labels in v1 | **Yes** | PRD. |
| 29 | Strict TDD without exceptions for v1 | **Yes** | [.agent/agent.md](agent.md). |
| 30 | CI (build + tests) required before tagging v1 | **Yes** | Release quality gate. |

**Override:** When you answer the 30 questions yourself, replace the **Assumed** column or add a **User** column.

---

## 2. Conflict resolution and gaps

| Topic | Conflict or gap | Resolution for v1 |
|-------|------------------|---------------------|
| Distribution | Q4 vs Q5 (outside store vs App Store) | **Ship v1 as notarized developer ID + GitHub Releases.** No Mac App Store for the v1 tag; revisit v1.1+. |
| Privacy vs Notes | Apple Notes export often needs sharing/UI work; MAS sandbox differs from Developer ID | Implement Notes via `NSSharingService` / share sheet where possible; test on **Developer ID** build first. Document if Notes is flaky → ship Markdown/PDF/zip as primary. |
| PRD vs Q13 | PRD includes smart name resolution | **Deferred to v1.1** per assumption table to limit LLM surface area for first tag. |
| PRD vs Q19 | Auto-delete audio | **Optional** in settings if schedule allows; not a v1 blocker. |
| Scope | Large v1 surface (diarization + chat + exports) | Milestones below order **riskiest** items early (MLX pipeline, diarization, memory). Cut order: name resolution (already out), then auto-delete, then non-English if schedule slips. |

---

## 3. v1 feature matrix

| Area | In v1 | Later |
|------|-------|--------|
| Platform | macOS 14+, Apple Silicon | Intel; older macOS |
| Ingest | Drag/drop, picker, audio + video extract, queue, pause/resume/cancel, limits | Live mic (PRD future-proofing) |
| Transcription | MLX Whisper, offline after model fetch | — |
| Diarization | Speaker 1, 2, … | — |
| Names | Manual edit of speaker labels | Smart LLM name resolution (PRD §2) |
| LLM | Summaries (≥1 template), chat with transcript | Extra templates, richer RAG |
| UI | 3-pane, SF Symbols, light/dark, `MenuBarExtra` | — |
| Data | SwiftData library, global search, clear all data | — |
| Export | Markdown, PDF, Apple Notes (best effort), zip/folder | Polish per-channel |
| Models | First-launch download + optional custom paths | Bundled retail build variant (optional) |
| Playback | Integrated player, timestamp seek | — |
| Editing | Full transcript edit | — |
| Quality | Strict TDD; CI before tag | — |

---

## 4. Milestone order (implementation)

Order respects dependencies and [.agent/agent.md](agent.md) (tests before UI where stated).

1. **Project skeleton** — Xcode macOS app, folder layout (Models, ViewModels, Views, Services), SwiftData schema stubs, dependency injection seams.
2. **Model download / paths** — Service for first-run fetch, disk layout, optional user model directory; unit tests with mocks.
3. **Audio pipeline** — Extract/decode, duration/size limits, queue with pause/resume/cancel; tests first.
4. **MLX transcription** — Whisper integration; progress reporting off main thread; tests with short fixtures.
5. **Diarization** — Integrate after baseline transcript works; fall back to single-speaker if model/API fails (feature-flag or user message).
6. **SwiftData persistence** — `Recording`, `Transcript`, segments, speakers; library CRUD; search index or predicates.
7. **Playback + sync** — AVFoundation player, current time → scroll/highlight; clickable timestamps.
8. **Transcript UI** — Editable text, speaker labels; 3-pane shell + library sidebar.
9. **LLM** — Load local model; summary template(s); chat with transcript context window; tests with mock LLM.
10. **Export** — Markdown, PDF, zip; Notes last (sharing).
11. **Settings** — Limits, clear all data, model path overrides, optional auto-delete if shipped.
12. **Menu bar extra** — Quick add / status.
13. **Hardening** — Memory caps, error UX, accessibility pass (minimum: keyboard, VoiceOver on main flows).
14. **CI** — `xcodebuild test` on Apple Silicon runner; tag only when green.
15. **Release** — Notarize, staple, GitHub Release notes, checksums.

```mermaid
flowchart LR
  skeleton[Project_skeleton]
  models[Model_download]
  audio[Audio_pipeline]
  mlx[MLX_transcription]
  diar[Diarization]
  data[SwiftData_library]
  play[Player_sync]
  ui3[Three_pane_UI]
  llm[LLM_summary_chat]
  export[Export]
  ship[Notarize_ship]
  skeleton --> models --> audio --> mlx --> diar --> data --> play --> ui3 --> llm --> export --> ship
```

---

## 5. Risks

| Risk | Mitigation |
|------|------------|
| MLX Whisper + LLM binary size and RAM | Streaming/chunked audio; quantize models; document min RAM; user-facing “insufficient memory” path. |
| Diarization quality or library maturity | Ship with clear “beta” labeling if needed; single-speaker fallback; tests on real meetings. |
| Apple Notes export under sandbox | Test early; fallback to Markdown/PDF. |
| TDD + full scope → long timeline | Strict milestone order; cut **name resolution** and **auto-delete** first if needed. |
| CI: MLX on runner | Use macOS ARM runner; cache models or small fixture models for tests. |

---

## 6. Release artifact (v1 tag)

- **Primary:** **Notarized** `.dmg` or `.zip` signed with **Developer ID**, released on **GitHub Releases** (open-source alignment with PRD).
- **Not in v1:** Mac App Store package (per §2).
- **Artifacts per release:** app bundle, `README` install notes, minimum OS/arch, model download expectations, checksum (e.g. SHA256).

---

## 7. Next step for you

1. Fill in your own Yes/No for the 30 questions (copy from the plan or §1 table).
2. Update §1–§3 if your answers differ — especially Q3 (language), Q5 (App Store), Q12–Q13 (chat / name resolution), Q19, Q22.

This file is the living **first release** contract until v1 ships.
