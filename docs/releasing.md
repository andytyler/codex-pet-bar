# Releasing CodexPetBar

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

## One Command

Patch release from the latest `vX.Y.Z` git tag:

```bash
cd /Users/ajt/Repos/projects/codex-pet-bar
./script/release_homebrew.sh
```

Minor or major release:

```bash
./script/release_homebrew.sh --bump minor
./script/release_homebrew.sh --bump major
```

Explicit version:

```bash
./script/release_homebrew.sh --version 0.1.1
```

The script prints each command before it runs, prints `OK` after success, and stops on the first failure with `FAIL`.

## What It Runs

1. Confirm the source repo is clean and on `main`.
2. Fetch tags and pick the next version from the latest `vX.Y.Z` tag.
3. Run validation:

   ```bash
   swift test
   python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'
   swift build -c release
   ```

4. Build the zip:

   ```bash
   VERSION=$VERSION ./script/package_app.sh --configuration release --zip --output /private/tmp/codexpet-release
   ```

5. Compute the zip SHA and update `Casks/codex-pet-bar.rb`.
6. Commit and push the source cask update.
7. Create GitHub release `v$VERSION` with the exact zip.
8. Copy the cask into `/opt/homebrew/Library/Taps/andytyler/homebrew-tap/Casks/codex-pet-bar.rb`.
9. Run:

   ```bash
   brew style --cask Casks/codex-pet-bar.rb
   brew audit --cask codex-pet-bar
   ```

10. Commit and push the tap.

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
