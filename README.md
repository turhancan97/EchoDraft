# EchoDraft

Offline-first macOS app for local transcription, diarization, summaries, and chat over your recordings. See [.agent/prd.md](.agent/prd.md) and [.agent/first-release-v1.md](.agent/first-release-v1.md).

## Requirements

- **macOS 15+** (Sequoia or later)
- **Xcode 16+** with the full Xcode app (not Command Line Tools alone). SwiftData `@Model` macros require the Xcode toolchain’s SwiftData macro plugin; builds must go through **`xcodebuild`** or opening **`EchoDraft.xcodeproj`** / the package in Xcode.
- **Apple Silicon** recommended for MLX inference.

## Project layout

```text
EchoDraft/
├── Package.swift              # Swift Package: EchoDraftCore + EchoDraft executable
├── EchoDraft.xcodeproj/       # Generated (XcodeGen) — commit for reliable Run/Archive
├── project.yml                # XcodeGen spec
├── Sources/
│   ├── EchoDraftCore/         # Models (SwiftData), services, view models, SwiftUI views
│   └── EchoDraftApp/          # @main app entry, Info.plist, menu bar extra
├── .github/workflows/ci.yml
└── .agent/                    # PRD and agent docs
```

## Build

### Recommended: Xcode

1. Open **`EchoDraft.xcodeproj`** (or open **`Package.swift`** in Xcode).
2. Select the **EchoDraft** scheme, destination **My Mac**, then **Run** (⌘R).

To regenerate the Xcode project after editing `project.yml`:

```bash
xcodegen generate
```

### Command line (requires full Xcode.app)

```bash
xcodebuild -project EchoDraft.xcodeproj -scheme EchoDraft -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Plain `swift build` is **not** supported for this package on CLT-only setups because **SwiftData** macros are not available there.

## First launch & data

- **Library:** SwiftData on-disk store (default location managed by the system). Legacy **`library.json`** in Application Support is migrated once into SwiftData and renamed to **`library.json.migrated`** (flag: `didMigrateJSONToSwiftData`).
- **MLX models:** STT (mlx-audio-swift / Qwen3-ASR by default) and LLM (mlx-swift-lm, default small instruct model) download from Hugging Face on first use, then run offline from the hub cache.

## Environment variables

| Variable | Effect |
|----------|--------|
| `ECHODRAFT_USE_STUB_ML=1` | Use `StubTranscriptionService` and `StubLLMService` (CI / fast dev without MLX). |
| `ECHODRAFT_STT_MODEL` | Hugging Face repo id for Qwen3-ASR weights (mlx-audio STT). |
| `ECHODRAFT_LLM_MODEL` | Hugging Face repo id for mlx-swift-lm (e.g. `mlx-community/...`). |
| `HF_TOKEN` | Optional token for private Hugging Face models. |

## Optional MLX integration tests

Heavy MLX tests are **not** run in the default GitHub Actions workflow. To add local-only tests, create a separate XCTest target in Xcode, point it at small fixtures, and run on your machine with models already cached.

## CI

The workflow builds with **`xcodebuild`** on **`macos-15`** and a recent Xcode (see workflow file). Stubs are enabled via `ECHODRAFT_USE_STUB_ML=1` so the job does not download large models.

## Release

Sign with **Developer ID**, **notarize**, distribute via **GitHub Releases** (see [.agent/first-release-v1.md](.agent/first-release-v1.md) §6).
