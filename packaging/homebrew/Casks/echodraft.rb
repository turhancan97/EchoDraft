# Template for a Homebrew tap (e.g. turhancan97/homebrew-tap).
# After each GitHub Release:
#   1. Set version to match the tag (without leading v).
#   2. Set sha256 to: shasum -a 256 EchoDraft-<version>.dmg
#   3. Confirm the download URL matches the Release asset name.

cask "echodraft" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHASUM_OF_PUBLISHED_DMG"

  url "https://github.com/turhancan97/EchoDraft/releases/download/v#{version}/EchoDraft-#{version}.dmg"
  name "EchoDraft"
  desc "Offline-first transcription, diarization, and LLM summaries for recordings"
  homepage "https://github.com/turhancan97/EchoDraft"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "EchoDraft.app"

  caveats <<~EOS
    EchoDraft downloads ML models from Hugging Face on first use. Apple Silicon recommended.
  EOS
end
