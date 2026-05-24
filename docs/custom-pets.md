# Custom Pets

CodexPetBar discovers pets in:

```text
~/.codex/pets/<pet-id>/
```

Each pet directory must contain a manifest and the spritesheet named by that manifest.

## Manifest

`pet.json` must contain these fields:

```json
{
  "id": "my-pet",
  "displayName": "My Pet",
  "description": "A short description.",
  "spritesheetPath": "spritesheet.webp"
}
```

Rules:

- `id` is the stable identifier used by CodexPetBar and Codex custom pet selection.
- `id` must match `[A-Za-z0-9][A-Za-z0-9._-]*`.
- `displayName` is shown in the menu.
- `description` is reserved for package metadata.
- `spritesheetPath` must be a relative path inside the pet directory.

## Spritesheet

The spritesheet must be exactly:

```text
1536 x 1872 pixels
8 columns x 9 rows
192 x 208 pixels per cell
```

Rows are fixed:

| Row | State | Used columns |
| --- | --- | --- |
| 0 | `idle` | 0-5 |
| 1 | `running-right` | 0-7 |
| 2 | `running-left` | 0-7 |
| 3 | `waving` | 0-3 |
| 4 | `jumping` | 0-4 |
| 5 | `failed` | 0-7 |
| 6 | `waiting` | 0-5 |
| 7 | `running` | 0-5 |
| 8 | `review` | 0-5 |

Unused cells may be transparent. Visible frames should fit inside their cells without crossing into neighboring cells.

## Validate

Validate a package before installing:

```bash
./script/validate_pet.py /path/to/my-pet
```

The validator checks:

- required manifest fields
- relative spritesheet path
- referenced spritesheet exists
- image dimensions are exactly `1536x1872`

## Install

Install a validated package:

```bash
./script/install_pet.sh /path/to/my-pet
```

This copies the package into:

```text
~/.codex/pets/<pet-id>
```

Use **Refresh Pets** from the CodexPetBar menu after installing or replacing a pet.

## Preview Installed Pets

Render state snapshots for an installed pet:

```bash
swift run CodexPetSnapshots --pet my-pet --output visual-testing/my-pet
```

This is useful when checking whether a spritesheet crops cleanly in the menu bar.
