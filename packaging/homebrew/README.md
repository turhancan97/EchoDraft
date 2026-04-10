# Homebrew tap template

Copy [Casks/echodraft.rb](Casks/echodraft.rb) into a **separate** tap repository (for example `turhancan97/homebrew-tap`) under `Casks/echodraft.rb`.

```bash
brew tap turhancan97/tap
brew install --cask echodraft
```

(Adjust tap name to match your GitHub user/org and tap repo.)

## After each EchoDraft release

1. Download `EchoDraft-<version>.dmg` from [GitHub Releases](https://github.com/turhancan97/EchoDraft/releases) or use `curl -LO` on the asset URL.
2. Run `shasum -a 256 EchoDraft-<version>.dmg`.
3. Update the cask `version`, `sha256`, and verify `url` matches  
   `https://github.com/turhancan97/EchoDraft/releases/download/v<version>/EchoDraft-<version>.dmg`.
4. Commit and push the tap; users get updates with `brew upgrade --cask echodraft`.

## Official Homebrew (`homebrew-cask`)

When ready, open a PR to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) using their cask naming and audit rules (`brew audit --cask --new echodraft`). Signed, notarized binaries improve acceptance.
