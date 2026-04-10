# Distribution strategy (EchoDraft)

This document records decisions for shipping via **GitHub Releases** (DMG), **Homebrew Cask**, and (later) **Sparkle**.

## Decisions

| Topic | Choice |
|--------|--------|
| Apple Developer Program | Enroll for **Developer ID** signing and **notarization** before serious public distribution. |
| CI secrets | Use **GitHub Actions encrypted secrets** only for signing and notarization credentials. |
| Until signing is ready | **Manual** Release uploads (build/sign/notarize locally) are OK; CI remains a **compile gate**. |
| Sparkle | **Deferred** until signed release builds are routine; see [SPARKLE.md](SPARKLE.md). |
| Architecture | **Apple Silicon (arm64)** only for distributed builds. |
| Installer | **Polished DMG** (volume name, window layout, link to `/Applications`; optional background image). |

## Contradiction resolved

Fully automated releases on GitHub-hosted runners **require** storing signing material in **encrypted secrets** (or an external signing service that still uses a token). There is no supported way to notarize in CI without passing Apple credentials securely.

## References

- [Homebrew Cask — adding a cask](https://docs.brew.sh/Cask-Cookbook)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- Repository workflow: [.github/workflows/release.yml](../.github/workflows/release.yml)
