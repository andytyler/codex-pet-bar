#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


EXPECTED_WIDTH = 1536
EXPECTED_HEIGHT = 1872
REQUIRED_FIELDS = ("id", "displayName", "description", "spritesheetPath")
PET_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Validate a CodexPetBar pet package.")
    parser.add_argument("pet_directory", help="Directory containing pet.json and spritesheet.webp")
    parser.add_argument("--print-id", action="store_true", help="Print only the pet id on success")
    args = parser.parse_args(argv[1:])

    try:
        manifest, spritesheet = validate(Path(args.pet_directory).expanduser())
    except ValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.print_id:
        print(manifest["id"])
    else:
        print(
            f"OK: {manifest['id']} ({manifest['displayName']}) "
            f"uses {spritesheet.name} at {EXPECTED_WIDTH}x{EXPECTED_HEIGHT}"
        )
    return 0


def validate(pet_directory: Path) -> tuple[dict, Path]:
    pet_directory = pet_directory.resolve()
    if not pet_directory.is_dir():
        raise ValidationError(f"{pet_directory} is not a directory")

    manifest_path = pet_directory / "pet.json"
    if not manifest_path.is_file():
        raise ValidationError(f"missing {manifest_path}")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValidationError(f"{manifest_path} is not valid JSON: {error}") from error

    if not isinstance(manifest, dict):
        raise ValidationError("pet.json must contain a JSON object")

    for field in REQUIRED_FIELDS:
        value = manifest.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValidationError(f"pet.json field {field!r} must be a non-empty string")

    if not PET_ID_PATTERN.fullmatch(manifest["id"]):
        raise ValidationError("pet id must match [A-Za-z0-9][A-Za-z0-9._-]*")

    spritesheet_path = Path(manifest["spritesheetPath"])
    if spritesheet_path.is_absolute() or ".." in spritesheet_path.parts:
        raise ValidationError("spritesheetPath must be a relative path inside the pet directory")

    spritesheet = pet_directory / spritesheet_path
    if not spritesheet.is_file():
        raise ValidationError(f"missing spritesheet: {spritesheet}")

    width, height = image_size(spritesheet)
    if (width, height) != (EXPECTED_WIDTH, EXPECTED_HEIGHT):
        raise ValidationError(
            f"spritesheet is {width}x{height}, expected {EXPECTED_WIDTH}x{EXPECTED_HEIGHT}"
        )

    if pet_directory.name != manifest["id"]:
        print(
            f"warning: folder name {pet_directory.name!r} differs from pet id {manifest['id']!r}; "
            "install_pet.sh will install by id",
            file=sys.stderr,
        )

    return manifest, spritesheet


def image_size(path: Path) -> tuple[int, int]:
    try:
        completed = subprocess.run(
            ["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError as error:
        raise ValidationError("sips is required on macOS to validate image dimensions") from error
    except subprocess.CalledProcessError as error:
        details = error.stderr.strip() or error.stdout.strip()
        raise ValidationError(f"could not read spritesheet dimensions: {details}") from error

    width = None
    height = None
    for line in completed.stdout.splitlines():
        key, _, value = line.strip().partition(":")
        if key == "pixelWidth":
            width = int(value.strip())
        elif key == "pixelHeight":
            height = int(value.strip())

    if width is None or height is None:
        raise ValidationError("sips did not report pixelWidth and pixelHeight")
    return width, height


class ValidationError(Exception):
    pass


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
