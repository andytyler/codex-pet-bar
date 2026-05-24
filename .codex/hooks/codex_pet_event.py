#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    payload = read_payload()
    event_name = payload.get("hook_event_name")

    try:
        event = normalize_event(payload)
        if event is not None:
            append_event(event, payload)
    finally:
        if event_name == "Stop":
            print(json.dumps({"continue": True}, separators=(",", ":")))

    return 0


def read_payload() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def normalize_event(payload: dict) -> dict | None:
    event_name = payload.get("hook_event_name")
    tool_name = payload.get("tool_name")

    kind_by_hook = {
        "SessionStart": "session_started",
        "UserPromptSubmit": "prompt_submitted",
        "PermissionRequest": "permission_requested",
        "Stop": "stopped",
    }

    if event_name == "PreToolUse":
        kind = "edit_started" if is_edit_tool(tool_name) else "tool_started"
    elif event_name == "PostToolUse":
        kind = "tool_failed" if tool_failed(payload.get("tool_response")) else "tool_succeeded"
    else:
        kind = kind_by_hook.get(event_name)

    if kind is None:
        return None

    event = {
        "version": 1,
        "timestamp": time.time(),
        "event": kind,
        "hook_event_name": event_name,
        "workspace": str(event_root(payload)),
    }

    for source_key, event_key in (
        ("session_id", "session_id"),
        ("turn_id", "turn_id"),
        ("tool_name", "tool_name"),
        ("permission_mode", "permission_mode"),
        ("model", "model"),
    ):
        value = payload.get(source_key)
        if isinstance(value, str) and value:
            event[event_key] = value

    prompt = payload.get("prompt")
    if isinstance(prompt, str):
        event["prompt_length"] = len(prompt)

    return event


def is_edit_tool(tool_name: object) -> bool:
    return tool_name in {"apply_patch", "Edit", "Write"}


def tool_failed(response: object) -> bool:
    if isinstance(response, dict):
        for key in ("exit_code", "exitCode", "returncode", "return_code", "status_code"):
            value = response.get(key)
            if isinstance(value, int) and value != 0:
                return True
        success = response.get("success")
        if isinstance(success, bool) and not success:
            return True
        status = response.get("status")
        if isinstance(status, str) and status.lower() in {"error", "failed", "failure"}:
            return True
        if response.get("error") is not None:
            return True
        return any(tool_failed(value) for value in response.values())

    if isinstance(response, list):
        return any(tool_failed(value) for value in response)

    return False


def append_event(event: dict, payload: dict) -> None:
    log_path = event_log_path(payload)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, separators=(",", ":"), sort_keys=True))
        handle.write("\n")


def event_log_path(payload: dict) -> Path:
    override = os.environ.get("CODEX_PET_EVENT_LOG")
    if override:
        return Path(override).expanduser()
    return event_root(payload) / ".codex" / "pet-events.jsonl"


def event_root(payload: dict) -> Path:
    override = os.environ.get("CODEX_PET_EVENT_ROOT")
    if override:
        return Path(override).expanduser().resolve()

    cwd = payload.get("cwd")
    start = Path(cwd if isinstance(cwd, str) and cwd else os.getcwd()).expanduser()
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
            return Path(root).resolve()
    except Exception:
        pass

    return start.resolve()


if __name__ == "__main__":
    raise SystemExit(main())
