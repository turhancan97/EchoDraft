# Packaging & release

See [DISTRIBUTION.md](DISTRIBUTION.md) for strategy. This folder holds DMG tooling and Homebrew templates.

## Prerequisites (maintainers)

- **Xcode** with the SwiftData toolchain (full `Xcode.app`).
- **XcodeGen** to regenerate the Xcode project after `project.yml` changes: `xcodegen generate`.
- **create-dmg** for disk images: `brew install create-dmg`.
- For signed/notarized releases: **Apple Developer Program**, **Developer ID Application** certificate, and API key or app-specific password for `notarytool`.

## Local: unsigned DMG (quick test)

```bash
DERIVED="$(pwd)/build/DerivedData"
xcodebuild -project EchoDraft.xcodeproj -scheme EchoDraft \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=- \
  build
./packaging/scripts/make-dmg.sh "1.0.0" "$DERIVED/Build/Products/Release/EchoDraft.app" ./build
shasum -a 256 build/EchoDraft-1.0.0.dmg
```

## Version numbers

- Bump **`MARKETING_VERSION`** / **`CURRENT_PROJECT_VERSION`** in [project.yml](../project.yml), then run `xcodegen generate`.
- Match Git tags: `v1.0.0` ↔ marketing version `1.0.0`.

## GitHub Actions: release workflow

[.github/workflows/release.yml](../.github/workflows/release.yml) runs on **`v*` tags** and produces an **unsigned** DMG plus `checksums.txt` attached to the GitHub Release.

### Optional secrets (signed + notarized CI — future)

When you are ready to automate signing in Actions, add **encrypted repository secrets** (names are conventional — align with your workflow if you customize):

| Secret | Purpose |
|--------|---------|
| `MACOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` (Developer ID Application). |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12`. |
| `KEYCHAIN_PASSWORD` | Temporary keychain password used only on the runner. |
| `APPLE_TEAM_ID` | 10-character Team ID. |
| `APPLE_ID` | Apple ID email for `notarytool`. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password (or prefer App Store Connect API key workflow). |

Then extend the release workflow to import the certificate, sign with **Developer ID**, run **`notarytool submit --wait`**, **`stapler staple`**, and upload the stapled DMG. Until then, sign and notarize **locally** and attach the DMG to a Release manually if needed.

## Homebrew

Template cask: [homebrew/Casks/echodraft.rb](homebrew/Casks/echodraft.rb). Copy into your tap repository (e.g. `homebrew-tap`) and update `version`, `sha256`, and `url` after each release.
