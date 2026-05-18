# Codex Menu Bar Pet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a native no-Dock macOS menu-bar app that animates the installed Codex pet and lets the user configure it from the menu.

**Architecture:** Use a SwiftPM package with an AppKit executable target and a small testable core library. The executable owns `NSApplication`, `NSStatusItem`, menus, image slicing, polling timers, and no-Dock accessory behavior; tests cover pet discovery, Codex state parsing, atlas mapping, and state selection logic.

**Tech Stack:** Swift 6, SwiftPM, AppKit, Foundation, XCTest, shell script app bundle staging.

---

## File Structure

- Create `Package.swift`: package manifest with `CodexPetBarCore`, `CodexPetBar`, and `CodexPetBarCoreTests`.
- Create `Sources/CodexPetBarCore/PetModels.swift`: pet metadata, animation state, activity state, size models.
- Create `Sources/CodexPetBarCore/PetLibrary.swift`: scan `~/.codex/pets`, parse `pet.json`, resolve spritesheet paths.
- Create `Sources/CodexPetBarCore/CodexState.swift`: parse `.codex-global-state.json`, map activity signals to pet animation states.
- Create `Sources/CodexPetBarCore/AppPreferences.swift`: `UserDefaults` preference wrapper.
- Create `Sources/CodexPetBar/PetSpriteSheet.swift`: AppKit image decode and 8x9 atlas slicing.
- Create `Sources/CodexPetBar/StatusPetController.swift`: status item, menu construction, timer-driven animation.
- Create `Sources/CodexPetBar/main.swift`: no-Dock AppKit app entrypoint.
- Create `Tests/CodexPetBarCoreTests/*.swift`: focused XCTest coverage for core behavior.
- Create `script/build_and_run.sh`: kill, build, bundle, launch, and verify app.
- Create `.codex/environments/environment.toml`: Codex Run action.
- Update `.gitignore`: ignore Swift build and dist artifacts.

## Task 1: Scaffold Package And Core Tests

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexPetBarCore/PetModels.swift`
- Create: `Tests/CodexPetBarCoreTests/PetLibraryTests.swift`

- [x] **Step 1: Write failing package/core tests**

Create `PetLibraryTests` with a fixture directory containing one valid pet, one invalid JSON pet, and one missing-spritesheet pet. Assert only the valid pet is returned and that display names sort alphabetically.

- [x] **Step 2: Run the test and verify RED**

Run: `swift test --filter PetLibraryTests`

Expected: failure because the package or `PetLibrary` does not exist yet.

- [x] **Step 3: Implement package manifest and minimal models/library**

Add the SwiftPM package and enough core code for pet discovery.

- [x] **Step 4: Run the test and verify GREEN**

Run: `swift test --filter PetLibraryTests`

Expected: tests pass.

## Task 2: Codex State And Preferences

**Files:**
- Create: `Sources/CodexPetBarCore/CodexState.swift`
- Create: `Sources/CodexPetBarCore/AppPreferences.swift`
- Create: `Tests/CodexPetBarCoreTests/CodexStateTests.swift`

- [x] **Step 1: Write failing tests**

Test that `selected-avatar-id: custom:goblin` resolves to `goblin`, that a manual pet override wins over the Codex selected pet, and that activity states map to expected animation rows.

- [x] **Step 2: Run tests and verify RED**

Run: `swift test --filter CodexStateTests`

Expected: failure because state parsing and preferences do not exist.

- [x] **Step 3: Implement state parsing and preference selection**

Add JSON parsing, preference keys, and deterministic selection precedence.

- [x] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter CodexStateTests`

Expected: tests pass.

## Task 3: Sprite Sheet And Status App

**Files:**
- Create: `Sources/CodexPetBar/PetSpriteSheet.swift`
- Create: `Sources/CodexPetBar/StatusPetController.swift`
- Create: `Sources/CodexPetBar/main.swift`

- [x] **Step 1: Write atlas mapping tests**

Add a core test that asserts the 8x9 atlas row mapping and durations match the Codex pet reference.

- [x] **Step 2: Run tests and verify RED**

Run: `swift test --filter AnimationAtlasTests`

Expected: failure because atlas metadata is missing.

- [x] **Step 3: Implement atlas metadata in core and AppKit image slicing in executable**

Keep testable metadata in core, and AppKit-only `NSImage` slicing in the executable target.

- [x] **Step 4: Implement AppKit status item**

Create no-Dock app startup, status item sizing, frame timer, menu commands, pet selector, follow-Codex toggle, size selector, state selector, refresh, open pets folder, and quit.

- [x] **Step 5: Run tests and build**

Run: `swift test`

Run: `swift build`

Expected: both pass.

## Task 4: Build/Run Integration

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`
- Create or modify: `.gitignore`

- [x] **Step 1: Add run script and Codex environment action**

The script builds the SwiftPM GUI executable, stages `dist/CodexPetBar.app`, writes a minimal `Info.plist` with `LSUIElement=true`, and launches with `/usr/bin/open -n`.

- [x] **Step 2: Verify script**

Run: `./script/build_and_run.sh --verify`

Expected: exit 0 and `pgrep -x CodexPetBar` finds the launched process.

## Task 5: Final Verification

**Files:**
- All app files.

- [x] **Step 1: Full tests**

Run: `swift test`

Expected: all tests pass.

- [x] **Step 2: Full build**

Run: `swift build`

Expected: build succeeds.

- [x] **Step 3: Launch app**

Run: `./script/build_and_run.sh --verify`

Expected: process is running and the app is visible as a menu-bar item with no Dock icon.

- [x] **Step 4: Commit implementation**

Stage source, test, script, config, and plan files; commit with message `Build Codex menu bar pet app`.
