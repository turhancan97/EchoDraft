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
├── EchoDraft.xcodeproj/       # XcodeGen output — committed for CI and archives
├── project.yml                # XcodeGen spec (edit this, then xcodegen generate)
├── Sources/
│   ├── EchoDraftCore/         # Models (SwiftData), services, view models, SwiftUI views
│   └── EchoDraftApp/          # @main app entry, Info.plist, menu bar extra
├── packaging/                 # DMG scripts, Homebrew cask template, distribution docs
├── .github/workflows/         # ci.yml, release.yml
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

CI and command-line checks use **`xcodebuild`** against **`EchoDraft.xcodeproj`** so SwiftData macros resolve. Plain `swift build` can work when the full Swift toolchain includes SwiftData macros, but the recommended path is Xcode / `xcodebuild`.

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

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on pushes and pull requests to `main` / `master`: **`xcodebuild`** on **`macos-15`** (Apple Silicon destination), **Debug** configuration, **`CODE_SIGNING_ALLOWED=NO`**. Runtime stubs are not required for compile-only CI; set `ECHODRAFT_USE_STUB_ML=1` locally when running the app without MLX.

## Release (GitHub + DMG)

1. Bump **`MARKETING_VERSION`** / **`CURRENT_PROJECT_VERSION`** in [`project.yml`](project.yml), run **`xcodegen generate`**, commit.
2. Tag and push: `git tag v1.0.0 && git push origin v1.0.0`.
3. [`.github/workflows/release.yml`](.github/workflows/release.yml) builds an **unsigned** **Release** app, runs [`packaging/scripts/make-dmg.sh`](packaging/scripts/make-dmg.sh), and attaches **`EchoDraft-<version>.dmg`** plus **`checksums.txt`** to the GitHub Release for that tag.

Manual test builds without a tag: run the **Release** workflow from the Actions tab (**workflow_dispatch**) and download the **artifact**.

For **Developer ID** signing and **notarization**, use your Apple account locally or add GitHub Actions secrets and extend the workflow (see [`packaging/README.md`](packaging/README.md)). Unsigned DMGs are fine for testing; public distribution should be signed and notarized. More checklist context: [.agent/first-release-v1.md](.agent/first-release-v1.md).

## Homebrew Cask

A cask template lives in [`packaging/homebrew/Casks/echodraft.rb`](packaging/homebrew/Casks/echodraft.rb). Copy it into your own tap repository (e.g. `turhancan97/homebrew-tap`) and update `version`, `sha256`, and `url` after each release. See [`packaging/homebrew/README.md`](packaging/homebrew/README.md). Submitting to the **main** Homebrew cask repo is optional once URLs and checksums are stable.

## Sparkle (auto-updates)

Deferred until signed releases are standard; see [`packaging/SPARKLE.md`](packaging/SPARKLE.md).
