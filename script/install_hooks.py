#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


GIT_HOOK_COMMAND = '/usr/bin/python3 "$(git rev-parse --show-toplevel)/.codex/hooks/codex_pet_event.py"'
HOOK_TIMEOUT = 5
HOOKS = [
    ("SessionStart", "startup|resume|clear"),
    ("UserPromptSubmit", None),
    ("PreToolUse", "*"),
    ("PermissionRequest", "*"),
    ("PostToolUse", "*"),
    ("Stop", None),
]


def main(argv: list[str]) -> int:
    try:
        target = parse_target(argv[1:])
    except ValueError as error:
        print(error, file=sys.stderr)
        print_usage()
        return 2

    repo_root = Path(__file__).resolve().parents[1]
    source_script = repo_root / ".codex" / "hooks" / "codex_pet_event.py"
    if not source_script.exists():
        print(f"Missing hook script: {source_script}", file=sys.stderr)
        return 1

    if target.kind == "global":
        install_global_hooks(source_script)
    else:
        install_workspace_hooks(source_script, target.path)

    return 0


class InstallTarget:
    def __init__(self, kind: str, path: Path | None = None) -> None:
        self.kind = kind
        self.path = path


def parse_target(args: list[str]) -> InstallTarget:
    if not args:
        return InstallTarget("global")

    if args[0] in {"-h", "--help"}:
        print_usage()
        raise SystemExit(0)

    if args[0] == "--global":
        if len(args) != 1:
            raise ValueError("--global does not take a workspace path.")
        return InstallTarget("global")

    if args[0] == "--workspace":
        if len(args) != 2:
            raise ValueError("--workspace requires exactly one path.")
        return InstallTarget("workspace", Path(args[1]).expanduser())

    if len(args) == 1:
        return InstallTarget("workspace", Path(args[0]).expanduser())

    raise ValueError("Too many arguments.")


def print_usage() -> None:
    print(
        """Usage: script/install_hooks.py [--global | --workspace <path> | <path>]

Installs CodexPetBar lifecycle hooks.

Default:
  script/install_hooks.py
    Install one user-level hook config in ~/.codex/hooks.json.

Workspace compatibility:
  script/install_hooks.py --workspace /path/to/repo
  script/install_hooks.py /path/to/repo
    Install hooks into /path/to/repo/.codex/hooks.json.
""",
        file=sys.stderr,
    )


def install_global_hooks(source_script: Path) -> None:
    target_codex = codex_home()
    target_hooks = target_codex / "hooks"
    target_hooks.mkdir(parents=True, exist_ok=True)
    target_script = target_hooks / "codex_pet_event.py"
    shutil.copy2(source_script, target_script)

    hooks_json = target_codex / "hooks.json"
    command = global_hook_command(target_codex, target_script)
    added = merge_hooks(hooks_json, command)

    print(f"Installed global hook script: {target_script}")
    print(f"Updated global hooks config: {hooks_json}")
    print(f"Global event log: {target_codex / 'pet-events.jsonl'}")
    print(f"Added hook entries: {added}")


def install_workspace_hooks(source_script: Path, requested_path: Path | None) -> None:
    if requested_path is None:
        raise SystemExit("Missing workspace path.")

    workspace, is_git_workspace = workspace_root(requested_path)
    target_codex = workspace / ".codex"
    target_hooks = target_codex / "hooks"
    target_hooks.mkdir(parents=True, exist_ok=True)
    target_script = target_hooks / "codex_pet_event.py"
    shutil.copy2(source_script, target_script)
    command = hook_command(workspace, target_script, is_git_workspace)

    hooks_json = target_codex / "hooks.json"
    added = merge_hooks(hooks_json, command)

    print(f"Installed workspace hook script: {target_script}")
    print(f"Updated workspace hooks config: {hooks_json}")
    print(f"Added hook entries: {added}")


def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", "~/.codex")).expanduser().resolve()


def global_hook_command(codex_home_path: Path, target_script: Path) -> str:
    return (
        f"CODEX_PET_EVENT_LOG={shlex.quote(str(codex_home_path / 'pet-events.jsonl'))} "
        f"/usr/bin/python3 {shlex.quote(str(target_script))}"
    )


def merge_hooks(hooks_json: Path, command: str) -> int:
    config = load_hooks_json(hooks_json)
    hooks = config.setdefault("hooks", {})

    added = 0
    for event_name, matcher in HOOKS:
        entries = hooks.setdefault(event_name, [])
        if not contains_command(entries, matcher, command):
            entries.append(hook_entry(matcher, command))
            added += 1

    hooks_json.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    return added


def workspace_root(path: Path) -> tuple[Path, bool]:
    start = path.resolve()
    if start.is_file():
        start = start.parent
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        )
        root = completed.stdout.strip()
        if root:
            return Path(root).resolve(), True
    except Exception:
        pass
    return start, False


def hook_command(workspace: Path, target_script: Path, is_git_workspace: bool) -> str:
    if is_git_workspace:
        return GIT_HOOK_COMMAND

    return (
        f"CODEX_PET_EVENT_ROOT={shlex.quote(str(workspace))} "
        f"/usr/bin/python3 {shlex.quote(str(target_script))}"
    )


def load_hooks_json(path: Path) -> dict:
    if not path.exists():
        return {"hooks": {}}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise SystemExit(f"Could not parse {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"{path} must contain a JSON object.")
    if "hooks" in value and not isinstance(value["hooks"], dict):
        raise SystemExit(f"{path} has a non-object hooks value.")
    return value


def hook_entry(matcher: str | None, command: str) -> dict:
    entry = {
        "hooks": [
            {
                "type": "command",
                "command": command,
                "timeout": HOOK_TIMEOUT,
            }
        ]
    }
    if matcher is not None:
        entry["matcher"] = matcher
    return entry


def contains_command(entries: object, matcher: str | None, command: str) -> bool:
    if not isinstance(entries, list):
        return False

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if entry.get("matcher") != matcher:
            continue
        hooks = entry.get("hooks")
        if not isinstance(hooks, list):
            continue
        for hook in hooks:
            if not isinstance(hook, dict):
                continue
            if hook.get("type") == "command" and hook.get("command") == command:
                return True
    return False


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
