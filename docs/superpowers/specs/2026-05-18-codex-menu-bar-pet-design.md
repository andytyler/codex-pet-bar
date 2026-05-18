# Codex Menu Bar Pet Design

Date: 2026-05-18

## Goal

Build a small native macOS menu-bar app that reuses the user's installed Codex pet as a Tamagotchi-style companion. The pet should live only in the menu bar, take up roughly a couple of centimeters, feel playful, and react to Codex activity when local Codex state exposes enough signal.

The app is intentionally menu-bar-only: no Dock icon and no main window at launch. Clicking the pet opens a compact configuration menu.

## Product Behavior

- The menu-bar pet animates continuously from the selected Codex pet spritesheet.
- On first launch, the app tries to use Codex's active avatar from `~/.codex/.codex-global-state.json`, specifically `selected-avatar-id` values such as `custom:goblin`.
- If active-pet detection fails, the app chooses the first valid pet under `~/.codex/pets`.
- The click menu always lets the user change the pet manually. The manual selection is persisted by the app and takes precedence until cleared or changed.
- When Codex appears idle, the pet uses a quiet nap/curl-up behavior based on the existing `waiting` or `idle` animation row. The app will not synthesize new pet art.
- When Codex activity is detected, the pet switches to a matching existing animation state:
  - `idle`: calm default when Codex is present but quiet.
  - `running`: Codex is actively working on a task.
  - `review`: Codex appears to be reading or reviewing.
  - `failed`: an error or failed state is detected.
  - `waving` or `jumping`: short playful reaction after pet changes or notable successful activity.
  - `running-right` / `running-left`: optional playful travel loops for short reactions, not a constant default.
- When transcription or dictation activity is detected, the pet enters a listening-style behavior using the closest available existing row, preferring `review` or `idle` if no dedicated listening row exists.

## Technical Approach

Use a native SwiftPM macOS app with AppKit at the status-item boundary.

Bun is not part of the core app because it does not help with native menu-bar integration. The right runtime for `NSStatusItem`, no-Dock accessory behavior, native menus, and low-overhead image animation is Swift/AppKit.

Core components:

- `CodexPetBarApp`: app entrypoint and no-Dock app lifecycle setup.
- `StatusPetController`: owns `NSStatusItem`, status button sizing, click menu, and frame updates.
- `PetLibrary`: scans `~/.codex/pets/*/pet.json`, validates each pet package, resolves relative `spritesheetPath`, and exposes selectable pets.
- `PetSpriteSheet`: loads the `spritesheet.webp`, slices the Codex 8x9 atlas into animation frames, and maps rows to named states.
- `PetAnimator`: selects states, advances frames, throttles animation, and handles temporary reactions.
- `CodexStateWatcher`: polls local Codex state files and SQLite/log metadata for best-effort activity signals without writing to Codex state.
- `AppPreferences`: persists selected pet override, size, idle behavior, and optional debug choices in `UserDefaults`.
- `MenuFactory`: builds the compact click menu with pet selector, size control, state/debug controls, refresh pets, and quit.

## Pet Asset Contract

The app reads standard Codex pet packages:

```text
~/.codex/pets/<pet-id>/
  pet.json
  spritesheet.webp
```

Current observed `pet.json` shape:

```json
{
  "id": "goblin",
  "displayName": "Goblin",
  "description": "A short pet description.",
  "spritesheetPath": "spritesheet.webp"
}
```

Current observed spritesheet geometry is `1536x1872`, which corresponds to 8 columns by 9 rows of `192x208` cells. The app treats that as the default Codex pet atlas layout and validates dimensions before use.

Animation row mapping:

| Row | State | Used columns | Default duration |
| --- | --- | ---: | --- |
| 0 | `idle` | 0-5 | 280, 110, 110, 140, 140, 320 ms |
| 1 | `running-right` | 0-7 | 120 ms each, final 220 ms |
| 2 | `running-left` | 0-7 | 120 ms each, final 220 ms |
| 3 | `waving` | 0-3 | 140 ms each, final 280 ms |
| 4 | `jumping` | 0-4 | 140 ms each, final 280 ms |
| 5 | `failed` | 0-7 | 140 ms each, final 240 ms |
| 6 | `waiting` | 0-5 | 150 ms each, final 260 ms |
| 7 | `running` | 0-5 | 120 ms each, final 220 ms |
| 8 | `review` | 0-5 | 150 ms each, final 280 ms |

If a row or frame cannot be rendered, the app falls back to `idle` and keeps running.

## Codex Activity Detection

The app only uses local, read-only signals. It does not depend on private Codex APIs and does not modify Codex files.

Initial signal sources:

- `~/.codex/.codex-global-state.json`
  - `selected-avatar-id` for the current Codex pet.
  - active workspace and overlay hints where available.
- `~/.codex/state_5.sqlite`
  - thread and job tables for recent or active local agent work.
- `~/.codex/logs_2.sqlite`
  - recent log rows for error or activity hints.
- `~/.codex/transcription-history.jsonl`
  - recent updates as a weak signal that dictation/transcription has just happened.

Activity detection is deliberately best-effort. If Codex changes file formats or locks a database, the watcher returns `unknown` and the pet keeps animating in idle or nap mode.

## Menu Design

Clicking the pet opens a native macOS menu with short labels:

- Current pet name, disabled.
- `Pets` submenu with all installed pets and a checkmark on the active selection.
- `Follow Codex Pet` toggle to use Codex's active avatar again.
- `Size` submenu with small, medium, and large menu-bar sprite sizes.
- `State` submenu for debug/manual state selection during development.
- `Refresh Pets`.
- `Open Pets Folder`.
- `Quit`.

Labels stay short so the menu remains compact and native.

## Error Handling

- Missing `~/.codex/pets`: show a small fallback symbol in the menu bar and a menu item explaining that no Codex pets were found.
- Invalid `pet.json`: skip that package and keep scanning.
- Missing or invalid spritesheet: list the pet as unavailable only if useful for debugging; otherwise skip it.
- Codex state parse failure: log the issue and continue with the app's selected pet.
- SQLite locked or unavailable: skip that polling cycle and try again later.
- Image decode failure: fall back to a simple system image so the app remains controllable.

## Testing And Verification

Verification will focus on behavior that can break a menu-bar app:

- Unit tests for pet package discovery, JSON parsing, atlas validation, row mapping, preference precedence, and activity-to-state mapping.
- Build verification through a project-local `script/build_and_run.sh`.
- Launch verification that the app starts as a bundled SwiftPM GUI app and appears without a Dock icon.
- Manual menu verification for pet switching, follow-Codex toggle, size changes, refresh, and quit.
- Visual sanity check that the status item animates frames and remains small enough for the menu bar.

## Out Of Scope For First Build

- Generating new pet art or new animation rows.
- Notarized release packaging.
- Launch-at-login.
- A large settings window.
- Network services or cloud sync.
- A Bun/Electron/webview runtime.

## Open Risks

- Codex local state formats are not a public stable API. The app must handle format changes gracefully.
- macOS menu-bar height constrains the sprite; some pet detail may be lost at very small sizes.
- There may not be a dedicated listening animation row. Dictation reactions will use the closest existing animation state.
