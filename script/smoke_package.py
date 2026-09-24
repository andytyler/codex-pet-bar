#!/usr/bin/env python3
"""Exercise every shipped helper through Homebrew-style symlinks in a private home."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import struct
import zlib
import tempfile

COMMANDS = ("codex-pet-bar", "codex-pet-install-hooks", "codex-pet-install-pet", "codex-pet-validate-pet")


def smoke(bundle: Path) -> None:
    bundle = bundle.resolve()
    scripts = bundle / "Contents/SharedSupport/bin"
    with tempfile.TemporaryDirectory(prefix="pet-package-smoke-") as temporary:
        root = Path(temporary).resolve()
        home = root / "home"
        home.mkdir()
        prefix = root / "homebrew/bin"
        prefix.mkdir(parents=True)
        links = root / "links"
        links.mkdir()
        environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(home),
                       "CODEX_HOME": str(home / "custom codex"), "CLAUDE_CONFIG_DIR": str(home / ".claude"),
                       "CURSOR_CONFIG_DIR": str(home / ".cursor"), "TMPDIR": str(root),
                       "PYTHONDONTWRITEBYTECODE": "1"}
        def run(command, *arguments):
            result = subprocess.run([str(command), *arguments], env=environment, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                raise RuntimeError(f"{command.name} {' '.join(arguments)} failed: {result.stderr}")
            return result
        for command in COMMANDS:
            executable = scripts / command
            if not executable.is_file() or not os.access(executable, os.X_OK):
                raise RuntimeError(f"Missing executable: {executable}")
            target = prefix / command
            target.symlink_to(executable)
            run(target, "--help")
            target.unlink()
            intermediate = links / command
            intermediate.symlink_to(os.path.relpath(executable, links))
            target.symlink_to(os.path.relpath(intermediate, prefix))
            run(target, "--help")
        run(prefix / "codex-pet-bar", "--add-hooks", "--help")
        run(prefix / "codex-pet-bar", "--add-codex-hooks", "--help")
        pet = root / "fixture-pet"
        pet.mkdir()
        (pet / "pet.json").write_text(json.dumps({"id": "fixture-pet", "displayName": "Fixture",
                                                  "description": "Package verification", "spritesheetPath": "spritesheet.png"}))
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        pixels = (b"\0" + b"\0" * (1536 * 4)) * 1872
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1536, 1872, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")
        (pet / "spritesheet.png").write_bytes(png)
        run(prefix / "codex-pet-validate-pet", str(pet))
        run(prefix / "codex-pet-install-pet", str(pet))
        installed = home / "custom codex/pets/fixture-pet"
        if (installed / "spritesheet.png").read_bytes() != png:
            raise RuntimeError("Pet installer did not use configured CODEX_HOME")
        repeat = subprocess.run([str(prefix / "codex-pet-install-pet"), str(installed)],
                                env=environment, capture_output=True, text=True, timeout=30)
        if repeat.returncode == 0 or (installed / "spritesheet.png").read_bytes() != png:
            raise RuntimeError("Pet reinstall did not protect its source")
        # Real generated wrappers and hook config writers, with foreign entries
        # proving uninstall removes only this application's integration.
        for directory, filename, config in (
            ("custom codex", "hooks.json", {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/usr/bin/true # foreign"}]}]}}),
            (".claude", "settings.json", {"theme": "dark", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/usr/bin/true # foreign"}]}]}}),
            (".cursor", "hooks.json", {"version": 1, "hooks": {"stop": [{"command": "/usr/bin/true # foreign"}]}}),
        ):
            path = home / directory / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(config))
        run(prefix / "codex-pet-bar", "--add-hooks", "--provider", "all")
        for path in (home / "custom codex/hooks.json", home / ".claude/settings.json", home / ".cursor/hooks.json"):
            if "codex_pet_event.py" not in path.read_text():
                raise RuntimeError(f"Provider integration missing: {path}")
        run(prefix / "codex-pet-install-hooks", "--provider", "all", "--remove-global")
        for path in (home / "custom codex/hooks.json", home / ".claude/settings.json", home / ".cursor/hooks.json"):
            text = path.read_text()
            if "foreign" not in text or "codex_pet_event.py" in text:
                raise RuntimeError(f"Provider uninstall failed to preserve foreign hooks: {path}")
    print("Package smoke passed: all four commands, absolute/relative/chained symlinks, pet validation/installation, and all-provider install/uninstall.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    smoke(args.bundle)
