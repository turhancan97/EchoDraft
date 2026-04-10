# Sparkle (deferred)

Automatic updates via **Sparkle 2** are **deferred** until:

1. **Developer ID** signing and **notarization** are routine for every release artifact.
2. Update packages are signed in a way Sparkle accepts (Sparkle’s security model expects properly signed updates).

## When you enable Sparkle

1. Add the **Sparkle 2** framework to the EchoDraft target (Swift Package or Xcode binary dependency).
2. Host an **appcast** (`appcast.xml`) — commonly:
   - Raw file on **GitHub Releases** (attach `appcast.xml` as a release asset), or
   - **`gh-pages`** branch with static hosting.
3. Point **SUFeedURL** in `Info.plist` at the appcast HTTPS URL.
4. For each release, publish the new build, update the appcast with enclosure URL, `length`, `edSignature` / Apple signing as required by your Sparkle setup.

## References

- [Sparkle documentation](https://sparkle-project.org/documentation/)
