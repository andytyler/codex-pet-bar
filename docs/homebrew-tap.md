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

Use the publish script from this repo:

```bash
./script/publish_homebrew.sh --version 0.1.0
```

By default it is a safe rehearsal. It:

1. checks the repo state
2. runs `swift test`
3. runs `python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'`
4. builds `CodexPetBar-0.1.0-macos.zip`
5. computes the zip SHA
6. updates [Casks/codex-pet-bar.rb](../Casks/codex-pet-bar.rb)
7. copies that cask into `/opt/homebrew/Library/Taps/andytyler/homebrew-tap/Casks/codex-pet-bar.rb`
8. runs `brew style --cask`
9. runs `brew audit --cask --new`

It does **not** create a GitHub release or push the tap unless you ask it to.

If `brew audit` is blocked by local Homebrew or Command Line Tools setup while you are only rehearsing, use:

```bash
./script/publish_homebrew.sh --version 0.1.0 --allow-dirty --skip-brew-audit
```

Do not skip `brew audit` for a real publish; update the local Command Line Tools first.

Full publish:

```bash
./script/publish_homebrew.sh \
  --version 0.1.0 \
  --repo andytyler/codex-pet-bar \
  --publish-release \
  --push-tap
```

Before full publish, the source repo must be committed and pushed to GitHub. The script checks that the current commit exists in `andytyler/codex-pet-bar`.

For a local rehearsal before the source repo is committed:

```bash
./script/publish_homebrew.sh --version 0.1.0 --allow-dirty
```

## What The Full Publish Does

1. **Checks the source repo.** Refuses full publish if there are uncommitted source changes.
2. **Checks the tap checkout.** Confirms `/opt/homebrew/Library/Taps/andytyler/homebrew-tap` is on `main`, points at `github.com/andytyler/homebrew-tap`, and is up to date.
3. **Tests the app.** Runs `swift test` and the Python hook unittest suite so the release is not built from a failing checkout.
4. **Builds the zip.** Runs `script/package_app.sh` and writes the zip under `/private/tmp/codexpet-release`.
5. **Computes Homebrew's SHA.** Homebrew verifies downloads by exact SHA, so the cask must match the uploaded zip byte-for-byte.
6. **Updates the cask.** Writes the new `version`, `sha256`, GitHub release URL, and homepage into `Casks/codex-pet-bar.rb`, then copies it into the tap.
7. **Runs Homebrew checks.** Runs `brew style --cask` and `brew audit --cask --new`.
8. **Publishes the GitHub release asset.** With `--publish-release`, verifies the current commit exists on GitHub, creates release `v0.1.0` if needed, and attaches the zip. If the asset already exists, the script downloads it and requires the SHA to match instead of replacing it.
9. **Pushes the tap.** With `--push-tap`, commits and pushes the cask update in `andytyler/homebrew-tap`.

After that, users install with:

```bash
brew tap andytyler/tap
brew install --cask codex-pet-bar
codex-pet-bar --add-codex-hooks
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
   brew audit --cask --new codex-pet-bar
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
