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
  "spritesheetPath": "spritesheet.webp",
  "spriteVersionNumber": 2
}
```

Rules:

- `id` is the stable identifier used by CodexPetBar and Codex custom pet selection.
- `id` must match `[A-Za-z0-9][A-Za-z0-9._-]*`.
- `displayName` is shown in the menu.
- `description` is reserved for package metadata.
- `spritesheetPath` must be a relative path inside the pet directory.
- `spriteVersionNumber` may be `1` or `2`. If omitted, it defaults to `1` for compatibility with existing pets.

## Spritesheet

Both sprite versions use 8 columns of `192 x 208` pixel cells:

```text
v1: 1536 x 1872 pixels (8 columns x 9 rows)
v2: 1536 x 2288 pixels (8 columns x 11 rows)
```

Rows 0-8 are fixed in both versions:

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

Version 2 adds 16 static gaze frames in rows 9-10. Heading `000` looks up, and the headings advance clockwise in 22.5-degree steps. Frames `000`-`007` occupy row 9 columns 0-7; frames `008`-`015` occupy row 10 columns 0-7.

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
- `spriteVersionNumber` is supported
- image dimensions match the declared sprite version

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

Choose the installed pet from **Pets** in the menu bar, then use the animation controls to check each state. Run `./script/validate_pet.py /path/to/my-pet` first to check the atlas dimensions and manifest.

Pet installation respects `CODEX_HOME`; when unset, it uses `~/.codex`. Reinstall from the original package folder rather than the installed destination.
