# Pet task UI and provider-flag design QA

Historical review from July 2026. The local reference/render paths below document the original UI work and are not release assets.

- Before render: `outputs/ui-audit-2026-07-21/01-current-task-panel.png`
- Boxed baseline: `outputs/ui-audit-2026-07-21/08-current-hover-before-flatten.png`
- Final dense render: `outputs/ui-audit-2026-07-21/09-dense-provider-panel.png`
- Final provider-flag render: `outputs/ui-audit-2026-07-21/10-unboxed-provider-flags.png`
- Packaged release panel: `outputs/ui-audit-2026-07-21/13-release-dense-provider-panel.png`
- Packaged release flags: `outputs/ui-audit-2026-07-21/14-release-unboxed-provider-flags.png`
- Panel comparison: `outputs/ui-audit-2026-07-21/11-boxed-vs-dense-panel.png`
- Provider-flag comparison: `outputs/ui-audit-2026-07-21/12-backed-vs-unboxed-flags.png`
- Compared state: light task panel with three tasks across two projects; dark menu-bar composition with two Codex, two Claude, and two Cursor scopes.

## Review

- Density: the 360 pt outer surface remains, while always-boxed 48 pt cards are now flat 38 pt rows with inset sibling dividers. The full three-task state is 194 pt, down from 242 pt in the immediate baseline and 358 pt in the original implementation.
- Hierarchy: pet, active count, and provider mix share one header row; project folders remain explicit; each task keeps a provider mark, title, summary, and state.
- Brand assets: Claude Code uses the official orange `clawd` crab and Cursor its official adaptive light/dark 2D cube. In-app Codex items use the Codex app icon; only tiny menu-bar Codex flags use the adaptive outline. The Pet Bar goblin remains app/pet identity only.
- Menu-bar flags: every ordinary active scope has its own unboxed provider mark. The status item expands when required so six mixed-provider flags remain individually readable. Waiting and failed flags pulse, use orange/red emphasis rings and attention markers, and render above the pet.
- Multiple sessions: provider and session form the stable identity, so concurrent sessions never collapse and a cwd change inside one session cannot create a phantom duplicate.
- Accessibility: the status item exposes task totals plus per-provider running, waiting, failed, and listening counts. Task rows retain labels, values, hints, and full-summary help.
- Motion and efficiency: provider SVGs are rasterized into a small bounded cache, existing 7 fps activity cadence is reused, Reduce Motion disables bobbing/pulsing, and no new timer or polling loop was added.
- Resilience: visual work is capped at 32 flags for corrupt/extreme logs; attention scopes are prioritized inside that defensive cap. The hover panel caps at 360 pt and scrolls longer lists.

## Resolved findings

- Fixed provider-first aggregation that previously could show only one icon per provider.
- Fixed same-session cwd drift creating duplicate Claude flags and leaving a phantom running state after stop.
- Matched failed attention retention to the 15-minute waiting window.
- Kept provider project cards pinned to the session's first stable workspace when later hooks report another cwd.
- Replaced the generic Claude Spark with Anthropic's official Claude Code crab throughout the panel, native menu, integrations menu, and menu-bar flags.
- Split provider art by context: in-app Codex rows use the Codex app icon while menu-bar flags retain the adaptive outline; the goblin remains only as app and pet identity.
- Removed normal provider backplates and the hover panel's always-on task cards, preserving subtle hover/focus feedback and attention-only flag emphasis.
- Verified the final panel and provider-flag composition visually; no clipping, unreadable overlap, or missing ordinary-scope flags remains.

final result: passed
