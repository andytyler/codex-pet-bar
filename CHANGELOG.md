# Changelog

## 0.3.3 (pending notarization)

- Make shared-pet clicks show the task panel before navigating, and keep background clicks responsive when Pet Bar is inactive.
- Replace hover boxes with a small pet enlargement, and give each waiting or failed pet a clear attention badge.
- Defer settings menu presentation until the initiating action returns, and make Escape dismissal reliable.

## 0.3.2 (pending notarization)

- Replace fixed task-pet slots with optional Shared pets: one continuous menu-bar area where working companions roam and idle companions stand.
- Keep finished companions visible, pause motion for interaction and Reduce Motion, and retain the single-companion default.
- Preserve earlier mode preferences and per-conversation pet assignments.

## 0.3.1 (pending notarization)

- Replace the task board with a compact native list: click any row to return to work, with recent tasks hidden until requested.
- Put display modes in settings and individual pet choices in a task’s context menu.
- Give each Codex conversation one stable pet, combining child-run activity under the real parent name.
- Resolve names for active conversations even when they fall outside the recent-history limit.
- Expire unrefreshed Codex running evidence after one hour, and retire cached active rows when their activity evidence expires.

## 0.3.0 (pending notarization)

- Add persistent task pet assignments and an optional menu bar with up to four task companions.
- Open task destinations directly and show navigation failures inline.

## 0.2.0 (pending notarization)

- Click the pet to keep tasks open; right-click for settings. Escape and outside clicks dismiss the panel.
- Put tasks needing input first and show readable status labels and an attention count.
- Connect individual agents in the task panel, with inline progress, repair actions and honest verification states. Unused agents remain optional.
- Preserve custom agent configuration directories when running connection installers.

- Follow local Codex, Claude Code and Cursor tasks with provider flags and project-grouped hover summaries.
- Run while work is active, show a brief Done indicator on completion, and return to a compact sleeping pet while idle.
- Ask once whether to open at login, with an Open at Login setting in the pet menu and support for macOS approval.
- Support custom v2 pets and cursor-aware animation.
- Preserve task state across event-log rotation, parallel permission requests, completed parents and resumed work.
- Safely replace installed pets, respect custom provider directories, and resolve Homebrew command symlinks.
- Recover from selection-file replacement, hover fade reentry and installer launch failures.
- Isolate installer tests from real settings, validate packaged commands, and add continuous integration.
- Publish the chosen landing page with complete installation and launch instructions.

Requires an Apple-Silicon Mac running macOS 14 or later. Remote/cloud agents are not connected.
