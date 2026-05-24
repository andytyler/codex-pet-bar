# Direct Distribution

Use this checklist when publishing CodexPetBar outside the Mac App Store, such as a GitHub release or direct download.

The App Store is not involved. Developer ID signing and notarization are still useful for third-party distribution because they make Gatekeeper trust the downloaded app without users needing to bypass warnings manually.

## Privacy Preflight

Confirm generated Codex state is not tracked in the release commit:

```bash
git ls-files .codex
git status --ignored --short .codex
```

The only `.codex` source file expected in the repo is:

```text
.codex/hooks/codex_pet_event.py
```

Check whether removed local files still exist in git history:

```bash
git log --all -- .codex/pet-events.jsonl .codex/environments/environment.toml
```

If those paths appear in history and the repo has already been pushed publicly, stop and purge them from history before release. A deletion commit only removes them from the current tree; it does not remove the old blobs.

## Local Validation

```bash
swift test
python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'
./script/package_app.sh --configuration release --zip --output /private/tmp/codexpet-release
codesign --verify --deep --strict /private/tmp/codexpet-release/CodexPetBar.app
```

Confirm the packaged app contains the SwiftPM resource bundle:

```bash
find /private/tmp/codexpet-release/CodexPetBar.app/Contents/Resources -maxdepth 2 -name '*.bundle' -print
```

## Developer ID Build

For a direct-download build that passes Gatekeeper cleanly, sign with a Developer ID Application certificate:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION=0.1.0 \
BUILD_NUMBER=1 \
./script/package_app.sh --configuration release --zip --output /private/tmp/codexpet-release
```

## Notarization For Direct Downloads

Submit the zip archive:

```bash
xcrun notarytool submit /private/tmp/codexpet-release/CodexPetBar-0.1.0-macos.zip \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait
```

Staple the ticket to the app, then recreate the zip:

```bash
xcrun stapler staple /private/tmp/codexpet-release/CodexPetBar.app
rm -f /private/tmp/codexpet-release/CodexPetBar-0.1.0-macos.zip
ditto -c -k --norsrc --keepParent \
  /private/tmp/codexpet-release/CodexPetBar.app \
  /private/tmp/codexpet-release/CodexPetBar-0.1.0-macos.zip
```

Validate the notarized artifact:

```bash
spctl --assess --type execute --verbose=4 /private/tmp/codexpet-release/CodexPetBar.app
```

## GitHub Release Notes

Include:

- macOS version requirement
- install command from `README.md`
- custom pet folder contract
- note that the global Codex activity hook is optional and installed with `codex-pet-bar --add-codex-hooks`
