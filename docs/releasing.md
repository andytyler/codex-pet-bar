# Releasing CodexPetBar

CodexPetBar releases are arm64-only and support Apple-Silicon Macs running macOS 14 or later. Building requires Swift 6.2+ (Xcode 26+).

Use a new version for every public app zip. Do not replace an existing release zip.

## Clean Repo Required

The release script refuses to run from a dirty source repo. This is deliberate: the GitHub release tag, uploaded zip, and Homebrew cask must describe the same committed code.

Check before releasing:

```bash
git status --short
```

Expected output:

```text
# no output
```

If you have scratch files, move them outside the repo or commit them before releasing. If you have real release changes, commit and push them first.

## Developer ID Setup

Homebrew can download an unsigned cask, but macOS Gatekeeper will block or warn on launch unless the app is signed with a Developer ID Application certificate and notarized.

Check whether the signing certificate is already installed:

```bash
security find-identity -p codesigning -v | grep "Developer ID Application"
```

If that prints nothing, create a **Developer ID Application** certificate in Apple Developer account **Certificates, Identifiers & Profiles**, download it, and double-click the `.cer` file so it appears in Keychain Access under **My Certificates**. You need the application certificate for this zip cask; **Developer ID Installer** is for signed `.pkg` installers.

Store notarization credentials once:

```bash
xcrun notarytool store-credentials codex-pet-bar-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

Enter an app-specific password when prompted. You can use a different profile name, but pass the same name to the release command with `--notary-profile`.

## One Command

Patch release from the latest `vX.Y.Z` git tag:

```bash
cd /path/to/codex-pet-bar
./script/publish_homebrew.sh \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  --notarize
```

Minor or major release:

```bash
./script/publish_homebrew.sh --bump minor --sign "Developer ID Application: YOUR NAME (TEAMID)" --notarize
./script/publish_homebrew.sh --bump major --sign "Developer ID Application: YOUR NAME (TEAMID)" --notarize
```

Explicit version:

```bash
./script/publish_homebrew.sh --version 0.1.1 --sign "Developer ID Application: YOUR NAME (TEAMID)" --notarize
```

The script prints each command before it runs, prints `OK` after success, and stops on the first failure with `FAIL`.

## Prepare Without Publishing

```bash
./script/publish_homebrew.sh --dry-run --version 0.2.0 \
  --output-dir /private/tmp/codexpet-release-0.2.0 \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" --notarize
```

This runs validation, signs and notarizes when requested, smoke-tests the actual packaged commands and stages the zip, cask and release manifest. It does not commit, push or create a release. `--dry-run` without signing/notarization is suitable for local packaging checks only.

Publishing requires a Developer ID identity and `--notarize`. Use `--yes` only when publication is already authorized; otherwise the script asks after complete artifacts exist. Source and tap checkouts must be clean on `main` and match their fetched remote branches.

## What It Runs

1. Fetch tags, validate the source checkout and repository identity, choose an unused version and check the tap.
2. Run Swift tests with the native build system and Python installer/release tests with isolated provider homes.
3. Assemble and sign the release app in private temporary storage with hardened runtime, then verify its signature.
4. Submit to Apple, staple and validate the notarization ticket, then create and verify the extracted zip before delivering versioned and stable-name assets. The app is also signature-checked. In File Provider managed output folders, only the zip is delivered there; the verified loose app stays in private temporary storage, recorded in `CodexPetBar-app-path.txt`.
5. Exercise the actual packaged commands through Homebrew-style symlinks in a temporary home, including pet replacement and all-provider hook installation/removal.
6. Compute SHA-256, stage the cask and source-commit manifest, and run Homebrew style and content audits against the exact staged cask. The unchanged token is checked locally; the global token catalogue is not rechecked.
7. After authorization, update the source cask, push its commit and create a GitHub release targeting that exact commit.
8. Copy the audited cask into the selected tap checkout, compare the bytes with the staged file, then commit and push the tap.

Apple must have an active agreement for the signing team. A notary-service agreement error must be resolved in the Apple Developer account before a public release; an ad hoc or unnotarized artifact is not a replacement.

The separate Website workflow checks, builds and publishes the chosen landing page to GitHub Pages. Native validation pins the preinstalled Xcode 26.2 toolchain on the GitHub `macos-15` runner and reports its Swift version before testing; the package requires Swift 6.2 or later.

## Install Check

After release:

```bash
brew update
brew install --cask andytyler/tap/codex-pet-bar
codex-pet-bar
```

## Privacy Check

Before publishing, this should print only the shipped hook source:

```bash
git ls-files .codex
```

Expected:

```text
.codex/hooks/codex_pet_event.py
```

This should print nothing:

```bash
git log --oneline --all -- .codex/pet-events.jsonl .codex/environments/environment.toml
```
