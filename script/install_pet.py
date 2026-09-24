#!/usr/bin/env python3
"""Validate and replace a custom pet without destroying a working installation."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import sys
import tempfile

from install_hooks import codex_home
from validate_pet import ValidationError, validate


def install(source: Path, pets: Path) -> Path:
    source = source.expanduser().resolve()
    manifest, _ = validate(source)
    # Resolve existing symlinked parents, but never follow/replace a pet symlink.
    destination = pets.resolve() / manifest["id"]
    resolved_destination = destination.resolve()
    if (source == resolved_destination or source in resolved_destination.parents
            or resolved_destination in source.parents):
        raise ValidationError("source and installed pet must be separate, non-nested directories")
    if destination.is_symlink():
        raise ValidationError("the installed pet path is a symlink; choose a separate pet id")
    if destination.exists() and not destination.is_dir():
        raise ValidationError("the installed pet path is not a directory")

    destination.parent.mkdir(parents=True, exist_ok=True)
    # Both renames stay on the destination filesystem. A failed copy or validation
    # leaves the old installation untouched; a failed final rename restores it.
    staging = Path(tempfile.mkdtemp(prefix=".pet-install-", dir=destination.parent))
    replacement = staging / "new" / manifest["id"]
    replacement.parent.mkdir()
    backup = staging / "previous"
    try:
        shutil.copytree(source, replacement)
        staged_manifest, _ = validate(replacement)
        if staged_manifest["id"] != manifest["id"]:
            raise ValidationError("pet id changed while the package was being copied")
        if destination.exists():
            os.rename(destination, backup)
        try:
            os.rename(replacement, destination)
        except BaseException:
            if backup.exists():
                os.rename(backup, destination)
            raise
    finally:
        # If a rollback itself failed, preserve the backup for recovery.
        if backup.exists() and not destination.exists():
            print(f"Previous pet preserved for recovery at: {backup}", file=sys.stderr)
        else:
            shutil.rmtree(staging)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description="Install a validated pet into $CODEX_HOME/pets (default: ~/.codex/pets).")
    parser.add_argument("pet_directory", type=Path)
    args = parser.parse_args()
    try:
        destination = install(args.pet_directory, codex_home() / "pets")
    except (ValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"Installed pet: {destination}")
    print(f"Use the CodexPetBar menu to Refresh Pets, then select {destination.name}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
