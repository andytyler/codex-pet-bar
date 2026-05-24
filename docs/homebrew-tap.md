# Homebrew Tap

CodexPetBar can be distributed outside the Mac App Store through the existing `andytyler/tap` Homebrew tap, like `catnav`.

This should be a Homebrew **cask** because it installs a native macOS menu bar app. The cask also exposes helper commands that are packaged inside `CodexPetBar.app`.

## User Install

After the cask is published to `andytyler/homebrew-tap`:

```bash
brew tap andytyler/tap
brew install --cask codex-pet-bar
codex-pet-bar
codex-pet-bar --add-codex-hooks
```

For one command:

```bash
brew install --cask andytyler/tap/codex-pet-bar
codex-pet-bar
codex-pet-bar --add-codex-hooks
```

## Helper Commands

The cask exposes:

```bash
codex-pet-bar
codex-pet-bar --add-codex-hooks
codex-pet-install-hooks
codex-pet-install-hooks --workspace /path/to/workspace
codex-pet-install-pet /path/to/pet
codex-pet-validate-pet /path/to/pet
```

Hooks are explicit because cask install should not mutate a user's Codex config automatically. The default hook install writes to `~/.codex/hooks.json`; the `--workspace` form is kept for project-local setups.

## Release Script

Use the publish script from a clean `main` checkout:

```bash
./script/publish_homebrew.sh
```

Minor, major, or explicit version releases:

```bash
./script/publish_homebrew.sh --bump minor
./script/publish_homebrew.sh --bump major
./script/publish_homebrew.sh --version 0.1.1
```

It:

1. picks the next patch version from the latest `vX.Y.Z` git tag unless `--version` is passed
2. checks the source repo is clean and on `main`
3. runs `swift test`
4. runs `python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'`
5. runs `python3 -m unittest discover -s Tests/HomebrewReleaseTests -p 'test_*.py'`
6. runs `swift build -c release`
7. builds `CodexPetBar-<version>-macos.zip`
8. computes the zip SHA
9. updates [Casks/codex-pet-bar.rb](../Casks/codex-pet-bar.rb)
10. commits and pushes the source cask update
11. creates the GitHub release and uploads the zip
12. copies the cask into `/opt/homebrew/Library/Taps/andytyler/homebrew-tap/Casks/codex-pet-bar.rb`
13. runs `brew style --cask`
14. runs `brew audit --cask codex-pet-bar`
15. commits and pushes the tap cask update

The script prints each command before it runs, prints `OK` after success, and stops on the first failure with `FAIL`.

## What The Full Publish Does

1. **Checks the source repo.** Refuses to continue unless the checkout is clean and on `main`.
2. **Tests the app and cask workflow.** Runs `swift test`, the Python hook unittest suite, the Homebrew release unittest suite, and `swift build -c release`.
3. **Builds the zip.** Runs `script/package_app.sh` and writes the zip under `/private/tmp/codexpet-release`.
4. **Computes Homebrew's SHA.** Homebrew verifies downloads by exact SHA, so the cask must match the uploaded zip byte-for-byte.
5. **Updates the source cask.** Writes the new `version` and `sha256` into `Casks/codex-pet-bar.rb`, then commits and pushes that source change.
6. **Publishes the GitHub release asset.** Creates release `v<version>` and attaches the zip.
7. **Updates the tap cask.** Pulls the tap checkout, copies the source cask into it, runs `brew style --cask` and `brew audit --cask codex-pet-bar`, then commits and pushes the tap cask update.

After that, users install with:

```bash
brew tap andytyler/tap
brew install --cask codex-pet-bar
codex-pet-bar --add-codex-hooks
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

## Manual Release Steps

1. Build the cask artifact:

   ```bash
   VERSION=0.1.0 ./script/package_app.sh --configuration release --zip --output /private/tmp/codexpet-release
   ```

2. Compute the SHA:

   ```bash
   shasum -a 256 /private/tmp/codexpet-release/CodexPetBar-0.1.0-macos.zip
   ```

3. Upload that exact zip to a GitHub release:

   ```text
   https://github.com/andytyler/codex-pet-bar/releases/tag/v0.1.0
   ```

4. Copy [Casks/codex-pet-bar.rb](../Casks/codex-pet-bar.rb) into:

   ```text
   andytyler/homebrew-tap:
     Casks/codex-pet-bar.rb
   ```

5. Replace the cask `sha256` with the SHA from step 2.

6. Test from the tap checkout:

   ```bash
   brew audit --cask codex-pet-bar
   brew install --cask ./Casks/codex-pet-bar.rb
   codex-pet-bar
   ```

## Updating

For each release:

1. Build a new zip.
2. Upload it to the matching GitHub release tag.
3. Update `version` and `sha256` in the tap cask.
4. Users upgrade with:

   ```bash
   brew update
   brew upgrade --cask codex-pet-bar
   ```
