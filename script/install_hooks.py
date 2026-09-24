#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


GIT_HOOK_SCRIPT = '"$(git rev-parse --show-toplevel)/.codex/hooks/codex_pet_event.py"'
HOOK_TIMEOUT = 5
PROVIDERS = ("codex", "claude", "cursor")
# Codex reports tool outcomes through PostToolUse and currently has no
# distinct failure or session-end hook config keys. Unknown keys invalidate
# hooks.json, so keep this list to events accepted by Codex itself.
CODEX_HOOKS = [
    ("SessionStart", "startup|resume|clear"),
    ("UserPromptSubmit", None),
    ("PreToolUse", "*"),
    ("PermissionRequest", "*"),
    ("PostToolUse", "*"),
    ("SubagentStart", "*"),
    ("SubagentStop", "*"),
    ("PreCompact", "manual|auto"),
    ("PostCompact", "manual|auto"),
    ("Stop", None),
]
CLAUDE_HOOKS = [
    ("SessionStart", "startup|resume|clear|compact"),
    ("UserPromptSubmit", None),
    ("PreToolUse", "*"),
    ("PermissionRequest", "*"),
    ("PermissionDenied", "*"),
    ("PostToolUse", "*"),
    ("PostToolUseFailure", "*"),
    ("Notification", "permission_prompt|idle_prompt|elicitation_dialog"),
    ("Elicitation", "*"),
    ("ElicitationResult", "*"),
    ("SubagentStart", "*"),
    ("SubagentStop", "*"),
    ("CwdChanged", None),
    ("PreCompact", "manual|auto"),
    ("PostCompact", "manual|auto"),
    ("Stop", None),
    ("StopFailure", None),
    ("SessionEnd", None),
]
# Cursor does not expose a native permission-request hook. Do not synthesize
# one from preToolUse: that event also fires for tools which need no approval.
CURSOR_HOOKS = (
    "sessionStart",
    "beforeSubmitPrompt",
    "preToolUse",
    "postToolUse",
    "postToolUseFailure",
    "afterAgentResponse",
    "subagentStart",
    "subagentStop",
    "preCompact",
    "stop",
    "sessionEnd",
)


def main(argv: list[str]) -> int:
    try:
        target = parse_target(argv[1:])
    except ValueError as error:
        print(error, file=sys.stderr)
        print_usage()
        return 2

    repo_root = Path(__file__).resolve().parents[1]
    source_script = repo_root / ".codex" / "hooks" / "codex_pet_event.py"
    if target.action == "remove":
        if target.kind == "global":
            remove_global_hooks(source_script if source_script.exists() else None, target.providers)
        else:
            remove_workspace_hooks(source_script if source_script.exists() else None, target.path)
        return 0

    if not source_script.exists():
        print(f"Missing hook script: {source_script}", file=sys.stderr)
        return 1

    if target.kind == "global":
        install_global_hooks(source_script, target.providers)
    else:
        install_workspace_hooks(source_script, target.path)

    return 0


class InstallTarget:
    def __init__(
        self,
        kind: str,
        path: Path | None = None,
        action: str = "install",
        providers: tuple[str, ...] = ("codex",),
    ) -> None:
        self.kind = kind
        self.path = path
        self.action = action
        self.providers = providers


def parse_target(args: list[str]) -> InstallTarget:
    args, providers = parse_provider_option(args)
    target = parse_location_and_action(args)
    if target.kind == "workspace" and providers != ("codex",):
        raise ValueError("Claude Code and Cursor hooks are user-level only; use --provider codex for a workspace.")
    target.providers = providers
    return target


def parse_provider_option(args: list[str]) -> tuple[list[str], tuple[str, ...]]:
    remaining: list[str] = []
    provider_name = "codex"
    found = False
    index = 0
    while index < len(args):
        argument = args[index]
        if argument == "--provider":
            if found:
                raise ValueError("--provider may be specified only once.")
            if index + 1 >= len(args):
                raise ValueError("--provider requires codex, claude, cursor, or all.")
            provider_name = args[index + 1].lower()
            found = True
            index += 2
            continue
        if argument.startswith("--provider="):
            if found:
                raise ValueError("--provider may be specified only once.")
            provider_name = argument.partition("=")[2].lower()
            found = True
            index += 1
            continue
        remaining.append(argument)
        index += 1

    if provider_name == "all":
        return remaining, PROVIDERS
    if provider_name not in PROVIDERS:
        raise ValueError("--provider requires codex, claude, cursor, or all.")
    return remaining, (provider_name,)


def parse_location_and_action(args: list[str]) -> InstallTarget:
    if not args:
        return InstallTarget("global")

    if args[0] in {"-h", "--help"}:
        print_usage()
        raise SystemExit(0)

    if args[0] == "--global":
        if len(args) != 1:
            raise ValueError("--global does not take a workspace path.")
        return InstallTarget("global")

    if args[0] == "--remove-global":
        if len(args) != 1:
            raise ValueError("--remove-global does not take a workspace path.")
        return InstallTarget("global", action="remove")

    if args[0] == "--remove":
        if len(args) == 1:
            return InstallTarget("global", action="remove")
        if len(args) == 2:
            return InstallTarget("workspace", Path(args[1]).expanduser(), action="remove")
        raise ValueError("--remove takes at most one workspace path.")

    if args[0] == "--remove-workspace":
        if len(args) != 2:
            raise ValueError("--remove-workspace requires exactly one path.")
        return InstallTarget("workspace", Path(args[1]).expanduser(), action="remove")

    if args[0] == "--workspace":
        if len(args) != 2:
            raise ValueError("--workspace requires exactly one path.")
        return InstallTarget("workspace", Path(args[1]).expanduser())

    if len(args) == 1:
        return InstallTarget("workspace", Path(args[0]).expanduser())

    raise ValueError("Too many arguments.")


def print_usage() -> None:
    print(
        """Usage: script/install_hooks.py [--provider codex|claude|cursor|all] [--global]
       script/install_hooks.py [--provider codex] [--workspace <path> | <path>]
       script/install_hooks.py [--provider codex|claude|cursor|all] [--remove-global | --remove]
       script/install_hooks.py [--provider codex] [--remove-workspace <path> | --remove <path>]

Installs CodexPetBar lifecycle hooks.

Default:
  script/install_hooks.py
    Install one user-level hook config in ~/.codex/hooks.json.

Provider selection:
  script/install_hooks.py --provider all
    Install Codex, Claude Code, and Cursor hooks into their user-level configs.

  script/install_hooks.py --provider claude
  script/install_hooks.py --provider cursor
    Install just that provider. Existing third-party hooks and settings are preserved.

Workspace compatibility:
  script/install_hooks.py --workspace /path/to/repo
  script/install_hooks.py /path/to/repo
    Install hooks into /path/to/repo/.codex/hooks.json.

Removal:
  script/install_hooks.py --remove-global
  script/install_hooks.py --remove
    Remove CodexPetBar entries from ~/.codex/hooks.json and clean copied files when safe.

  script/install_hooks.py --provider all --remove-global
    Remove CodexPetBar entries from all three user-level configs.

  script/install_hooks.py --remove-workspace /path/to/repo
  script/install_hooks.py --remove /path/to/repo
    Remove CodexPetBar entries from /path/to/repo/.codex/hooks.json.
""",
        file=sys.stderr,
    )


def install_global_hooks(source_script: Path, providers: tuple[str, ...]) -> None:
    target_codex = codex_home()
    target_hooks = target_codex / "hooks"
    ensure_private_directory(target_codex)
    ensure_private_directory(target_hooks)
    target_script = target_hooks / "codex_pet_event.py"
    shutil.copy2(source_script, target_script)
    chmod_private(target_script, 0o700)
    chmod_private(target_codex / "pet-events.jsonl", 0o600, missing_ok=True)
    chmod_private(target_codex / "pet-events.jsonl.1", 0o600, missing_ok=True)
    chmod_private(target_codex / "pet-events.jsonl.lock", 0o600, missing_ok=True)

    print(f"Installed global hook script: {target_script}")
    print(f"Global event log: {target_codex / 'pet-events.jsonl'}")

    for provider in providers:
        command = global_hook_command(target_codex, target_script, provider)
        if provider == "codex":
            config_path = target_codex / "hooks.json"
            added = merge_grouped_hooks(
                config_path,
                command,
                CODEX_HOOKS,
                legacy_global_commands(target_codex, target_script),
            )
        elif provider == "claude":
            config_path = claude_settings_path()
            added = merge_grouped_hooks(config_path, command, CLAUDE_HOOKS)
        else:
            config_path = cursor_hooks_path()
            added = merge_cursor_hooks(config_path, command)
        chmod_private(config_path, 0o600)
        print(f"Updated {provider_display_name(provider)} hooks config: {config_path}")
        print(f"Added {provider_display_name(provider)} hook entries: {added}")


def install_workspace_hooks(source_script: Path, requested_path: Path | None) -> None:
    if requested_path is None:
        raise SystemExit("Missing workspace path.")

    target_global_codex = codex_home()
    ensure_private_directory(target_global_codex)
    chmod_private(target_global_codex / "pet-events.jsonl", 0o600, missing_ok=True)
    chmod_private(target_global_codex / "pet-events.jsonl.1", 0o600, missing_ok=True)
    chmod_private(target_global_codex / "pet-events.jsonl.lock", 0o600, missing_ok=True)

    workspace, is_git_workspace = workspace_root(requested_path)
    target_codex = workspace / ".codex"
    target_hooks = target_codex / "hooks"
    target_hooks.mkdir(parents=True, exist_ok=True)
    target_script = target_hooks / "codex_pet_event.py"
    shutil.copy2(source_script, target_script)
    event_log = codex_home() / "pet-events.jsonl"
    command = hook_command(workspace, target_script, is_git_workspace, event_log)
    stale_commands = legacy_workspace_commands(workspace, target_script, is_git_workspace)

    hooks_json = target_codex / "hooks.json"
    added = merge_grouped_hooks(hooks_json, command, CODEX_HOOKS, stale_commands)

    print(f"Installed workspace hook script: {target_script}")
    print(f"Updated workspace hooks config: {hooks_json}")
    print(f"Workspace event log: {event_log}")
    print(f"Added hook entries: {added}")


def remove_global_hooks(source_script: Path | None, providers: tuple[str, ...]) -> None:
    target_codex = codex_home()
    target_script = target_codex / "hooks" / "codex_pet_event.py"
    event_log = target_codex / "pet-events.jsonl"
    for provider in providers:
        config_path = provider_config_path(provider)
        command = global_hook_command(target_codex, target_script, provider)
        commands = {command}
        if provider == "codex":
            commands.update(legacy_global_commands(target_codex, target_script))
        if provider == "cursor":
            removed = remove_cursor_hooks(config_path, commands)
        else:
            removed = remove_grouped_hooks(config_path, commands)
        print(f"Removed {provider_display_name(provider)} hook entries: {removed}")
        if config_path.exists():
            print(f"Updated {provider_display_name(provider)} hooks config: {config_path}")

    is_referenced = shared_hook_is_referenced(target_script)
    removed_script = False if is_referenced else remove_copied_hook_script(target_script, source_script)
    removed_log = False if is_referenced else remove_empty_event_log(event_log)
    if not is_referenced:
        remove_empty_directory(target_script.parent)

    if removed_script:
        print(f"Removed copied hook script: {target_script}")
    if removed_log:
        print(f"Removed empty event log: {event_log}")


def remove_workspace_hooks(source_script: Path | None, requested_path: Path | None) -> None:
    if requested_path is None:
        raise SystemExit("Missing workspace path.")

    workspace, is_git_workspace = workspace_root(requested_path)
    target_script = workspace / ".codex" / "hooks" / "codex_pet_event.py"
    event_log = codex_home() / "pet-events.jsonl"
    hooks_json = workspace / ".codex" / "hooks.json"
    commands = {hook_command(workspace, target_script, is_git_workspace, event_log)}
    commands.update(legacy_workspace_commands(workspace, target_script, is_git_workspace))

    removed = remove_grouped_hooks(hooks_json, commands)
    removed_script = remove_copied_hook_script(target_script, source_script)
    remove_empty_directory(target_script.parent)

    print(f"Removed workspace hook entries: {removed}")
    if hooks_json.exists():
        print(f"Updated workspace hooks config: {hooks_json}")
    if removed_script:
        print(f"Removed copied hook script: {target_script}")


def codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME", "").strip()
    home = Path.home()
    if not configured:
        return (home / ".codex").resolve()
    if configured == "~":
        return home.resolve()
    if configured.startswith("~/"):
        return (home / configured[2:]).resolve()
    return Path(configured).resolve()


def claude_settings_path() -> Path:
    configured = os.environ.get("CLAUDE_CONFIG_DIR")
    directory = Path(configured).expanduser() if configured else Path("~/.claude").expanduser()
    return directory.resolve() / "settings.json"


def cursor_hooks_path() -> Path:
    configured = os.environ.get("CURSOR_CONFIG_DIR")
    directory = Path(configured).expanduser() if configured else Path("~/.cursor").expanduser()
    return directory.resolve() / "hooks.json"


def provider_config_path(provider: str) -> Path:
    if provider == "codex":
        return codex_home() / "hooks.json"
    if provider == "claude":
        return claude_settings_path()
    return cursor_hooks_path()


def provider_display_name(provider: str) -> str:
    return {"codex": "Codex", "claude": "Claude Code", "cursor": "Cursor"}[provider]


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    chmod_private(path, 0o700)


def chmod_private(path: Path, mode: int, missing_ok: bool = False) -> None:
    if missing_ok and not path.exists():
        return
    try:
        if not path.is_symlink():
            path.chmod(mode)
    except OSError as error:
        print(f"Warning: could not chmod {path}: {error}", file=sys.stderr)


def global_hook_command(codex_home_path: Path, target_script: Path, provider: str = "codex") -> str:
    # Cursor imports the Claude-compatible hooks it supports. Its current hook
    # runner can therefore start the provider-specific Claude command as well
    # as the native Cursor command for the same event. Keep the commands distinct:
    # an environment-only Cursor guard can also suppress real Claude Code runs
    # launched from Cursor. The normalizer rejects mismatched event names, so
    # the imported invocation does not duplicate an event-log record.
    return (
        f"CODEX_PET_PROVIDER={provider} "
        f"CODEX_PET_EVENT_LOG={shlex.quote(str(codex_home_path / 'pet-events.jsonl'))} "
        f"/usr/bin/python3 {shlex.quote(str(target_script))}"
    )


def legacy_global_commands(codex_home_path: Path, target_script: Path) -> list[str]:
    return [
        (
            f"CODEX_PET_EVENT_LOG={shlex.quote(str(codex_home_path / 'pet-events.jsonl'))} "
            f"/usr/bin/python3 {shlex.quote(str(target_script))}"
        )
    ]


def merge_grouped_hooks(
    hooks_json: Path,
    command: str,
    hook_specs: list[tuple[str, str | None]],
    stale_commands: list[str] | None = None,
) -> int:
    config = load_hooks_json(hooks_json)
    hooks = config.setdefault("hooks", {})
    stale_command_set = set(stale_commands or [])
    desired_event_names = {event_name for event_name, _ in hook_specs}

    # Reconcile older CodexPetBar versions when an upstream lifecycle surface
    # changes. Remove only our exact command from obsolete event keys and leave
    # every foreign hook untouched.
    obsolete_commands = {command} | stale_command_set
    for event_name, entries in list(hooks.items()):
        if event_name in desired_event_names:
            continue
        filtered_entries, removed_count = remove_hook_commands_with_count(
            entries,
            obsolete_commands,
        )
        if removed_count > 0 and filtered_entries == []:
            del hooks[event_name]
        else:
            hooks[event_name] = filtered_entries

    added = 0
    for event_name, matcher in hook_specs:
        entries = hooks.setdefault(event_name, [])
        if not isinstance(entries, list):
            raise SystemExit(f"{hooks_json} has a non-array {event_name} hook value.")
        if stale_command_set:
            entries = remove_hook_commands(entries, stale_command_set)
            hooks[event_name] = entries
        if not contains_command(entries, matcher, command):
            entries.append(hook_entry(matcher, command))
            added += 1

    write_json_config(hooks_json, config)
    return added


def remove_grouped_hooks(hooks_json: Path, commands: set[str]) -> int:
    if not hooks_json.exists():
        return 0

    config = load_hooks_json(hooks_json)
    hooks = config.setdefault("hooks", {})
    removed = 0

    for event_name, entries in list(hooks.items()):
        filtered_entries, removed_count = remove_hook_commands_with_count(entries, commands)
        hooks[event_name] = filtered_entries
        removed += removed_count

    write_json_config(hooks_json, config)
    return removed


def merge_cursor_hooks(hooks_json: Path, command: str) -> int:
    config = load_hooks_json(hooks_json)
    config.setdefault("version", 1)
    hooks = config.setdefault("hooks", {})

    for event_name, entries in list(hooks.items()):
        if event_name in CURSOR_HOOKS or not isinstance(entries, list):
            continue
        filtered_entries = [
            entry
            for entry in entries
            if not (isinstance(entry, dict) and entry.get("command") == command)
        ]
        if len(filtered_entries) < len(entries) and not filtered_entries:
            del hooks[event_name]
        else:
            hooks[event_name] = filtered_entries

    added = 0
    for event_name in CURSOR_HOOKS:
        entries = hooks.setdefault(event_name, [])
        if not isinstance(entries, list):
            raise SystemExit(f"{hooks_json} has a non-array {event_name} hook value.")
        if not cursor_contains_command(entries, command):
            entries.append({"command": command, "timeout": HOOK_TIMEOUT})
            added += 1
    write_json_config(hooks_json, config)
    return added


def remove_cursor_hooks(hooks_json: Path, commands: set[str]) -> int:
    if not hooks_json.exists():
        return 0

    config = load_hooks_json(hooks_json)
    hooks = config.setdefault("hooks", {})
    removed = 0
    for event_name, entries in list(hooks.items()):
        if not isinstance(entries, list):
            continue
        filtered = []
        for entry in entries:
            if isinstance(entry, dict) and entry.get("command") in commands:
                removed += 1
            else:
                filtered.append(entry)
        hooks[event_name] = filtered
    write_json_config(hooks_json, config)
    return removed


def cursor_contains_command(entries: object, command: str) -> bool:
    return isinstance(entries, list) and any(
        isinstance(entry, dict) and entry.get("command") == command
        for entry in entries
    )


def shared_hook_is_referenced(target_script: Path) -> bool:
    target = str(target_script)
    for provider in PROVIDERS:
        config_path = provider_config_path(provider)
        if not config_path.exists():
            continue
        try:
            config = json.loads(config_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            # When a config cannot be inspected, retain the shared script rather
            # than risk breaking a hook that may still reference it.
            return True
        if json_value_contains(config, target):
            return True
    return False


def json_value_contains(value: object, needle: str) -> bool:
    if isinstance(value, str):
        return needle in value
    if isinstance(value, list):
        return any(json_value_contains(child, needle) for child in value)
    if isinstance(value, dict):
        return any(json_value_contains(child, needle) for child in value.values())
    return False


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


def hook_command(workspace: Path, target_script: Path, is_git_workspace: bool, event_log: Path) -> str:
    env = (
        f"CODEX_PET_EVENT_LOG={shlex.quote(str(event_log))} "
        f"CODEX_PET_EVENT_ROOT={shlex.quote(str(workspace))}"
    )
    return (
        f"{env} /usr/bin/python3 {shlex.quote(str(target_script))}"
    )


def legacy_workspace_commands(workspace: Path, target_script: Path, is_git_workspace: bool) -> list[str]:
    commands = [
        (
            f"CODEX_PET_EVENT_ROOT={shlex.quote(str(workspace))} "
            f"/usr/bin/python3 {shlex.quote(str(target_script))}"
        )
    ]
    if is_git_workspace:
        commands.append(f"/usr/bin/python3 {GIT_HOOK_SCRIPT}")
    return commands


def remove_hook_commands(entries: object, commands: set[str]) -> object:
    filtered_entries, _ = remove_hook_commands_with_count(entries, commands)
    return filtered_entries


def remove_hook_commands_with_count(entries: object, commands: set[str]) -> tuple[object, int]:
    if not isinstance(entries, list):
        return entries, 0

    filtered_entries = []
    removed = 0
    for entry in entries:
        if not isinstance(entry, dict):
            filtered_entries.append(entry)
            continue

        hooks = entry.get("hooks")
        if not isinstance(hooks, list):
            filtered_entries.append(entry)
            continue

        filtered_hooks = []
        for hook in hooks:
            if (
                isinstance(hook, dict)
                and hook.get("type") == "command"
                and hook.get("command") in commands
            ):
                removed += 1
                continue
            filtered_hooks.append(hook)
        if filtered_hooks:
            updated_entry = dict(entry)
            updated_entry["hooks"] = filtered_hooks
            filtered_entries.append(updated_entry)

    return filtered_entries, removed


def remove_copied_hook_script(target_script: Path, source_script: Path | None) -> bool:
    if not target_script.exists() or target_script.is_symlink():
        return False
    if source_script is None or not source_script.exists():
        return False
    try:
        if target_script.read_bytes() != source_script.read_bytes():
            return False
    except OSError:
        return False
    try:
        target_script.unlink()
    except OSError as error:
        print(f"Warning: could not remove copied hook script {target_script}: {error}", file=sys.stderr)
        return False
    return True


def remove_empty_event_log(event_log: Path) -> bool:
    if not event_log.exists() or event_log.is_symlink():
        return False
    try:
        if event_log.stat().st_size != 0:
            return False
        event_log.unlink()
    except OSError as error:
        print(f"Warning: could not remove empty event log {event_log}: {error}", file=sys.stderr)
        return False
    return True


def remove_empty_directory(path: Path) -> bool:
    try:
        path.rmdir()
    except OSError:
        return False
    return True


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


def write_json_config(path: Path, config: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Never truncate provider settings on a failed write. Resolve a deliberate
    # user config symlink and replace only its target after the complete write.
    path = path.resolve()
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(config, indent=2) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


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
