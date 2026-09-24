# Homebrew Tap

CodexPetBar is distributed as a Homebrew cask through `andytyler/tap`. It installs a native macOS menu bar app and helper commands packaged inside `CodexPetBar.app`. It requires an Apple-Silicon Mac running macOS 14 or later.

Public downloads and Homebrew currently provide v0.1.2. The v0.2.0 source and provider commands described below are pending Apple notarization; the tap must remain on the existing release until a notarized v0.2.0 artifact is ready.

## User Install

```bash
brew install --cask andytyler/tap/codex-pet-bar
codex-pet-bar
```

The existing Codex hook command works with the public release:

```bash
codex-pet-bar --add-codex-hooks
```

Open Codex and approve newly installed hooks there. Hook-driven reactions begin when Codex approves and runs those hooks.

## v0.2.0 Helper Commands

```bash
codex-pet-bar
codex-pet-bar --add-hooks --provider all
codex-pet-install-hooks
codex-pet-install-hooks --provider all
codex-pet-install-hooks --provider claude
codex-pet-install-hooks --provider cursor
codex-pet-install-hooks --remove-global
codex-pet-install-hooks --provider all --remove-global
codex-pet-install-hooks --workspace /path/to/workspace
codex-pet-install-hooks --remove-workspace /path/to/workspace
codex-pet-install-pet /path/to/pet
codex-pet-validate-pet /path/to/pet
```

Hooks are explicit: installing the cask does not change agent configuration automatically. The default hook install remains Codex-only and writes to `~/.codex/hooks.json`. `--provider all` additionally merges Claude Code and native Cursor hooks into their configured user directories while preserving foreign hooks. Workspace installation is Codex-only.

## Signed and Notarized Release

Building requires Swift 6.2+ (Xcode 26+). Start from clean source and tap checkouts on `main`, each matching its fetched remote branch. Commit and push the reviewed source before preparing a release. Use an unused version; never replace an existing public zip.

Check for a Developer ID Application identity, then store notarization credentials if needed:

```bash
security find-identity -p codesigning -v
xcrun notarytool store-credentials codex-pet-bar-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

Enter an app-specific password when prompted. A zipped `.app` requires a **Developer ID Application** certificate. Apple must have an active agreement for the signing team before notarization can succeed.

Prepare and inspect a release without publishing:

```bash
./script/publish_homebrew.sh --dry-run --version 0.2.0 \
  --output-dir /private/tmp/codexpet-release-0.2.0 \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  --notarize
```

This still signs, submits to Apple and staples the result. It creates the zip, staged cask and source-commit manifest, but makes no commits, pushes or GitHub releases. An unsigned dry run is only a local packaging check.

Publish the reviewed version:

```bash
./script/publish_homebrew.sh --version 0.2.0 \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  --notarize
```

The publication command prepares and validates artifacts again, then asks for confirmation. Use `--yes` only when publication is already authorized. Omit `--version` for the next patch version, or use `--bump minor` or `--bump major`; signing and notarization remain required for every public release.

The script performs these steps in order:

1. Fetch source tags, validate repository identity and clean source/tap branches, and reject an existing release version.
2. Run Swift tests and isolated Python installer/release tests, then build the release app.
3. Sign with hardened runtime, verify the signature, submit to Apple, staple and validate the notarization ticket, and verify the extracted final zip.
4. Smoke-test the actual packaged commands through Homebrew-style symlinks in a temporary home.
5. Compute SHA-256 and prepare a cask and source-commit manifest. Run Homebrew style and content audits against that exact staged cask before publishing.
6. After authorization, copy the staged cask into the source checkout, commit and push it, then create a GitHub release targeting that exact commit and upload the versioned and stable-name zip assets.
7. Copy the audited cask to the configured tap checkout, verify identical bytes, then commit and push the tap.

It prints each operation, stops on failure, and refuses public publication without signing and notarization. A notary-service agreement error must be resolved before publishing; an unnotarized build must not replace the public release.

See [Releasing CodexPetBar](releasing.md) for packaging details, privacy checks and post-release installation checks.
