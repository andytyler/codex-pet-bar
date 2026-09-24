#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import time
import fcntl
from pathlib import Path


MAX_TOOL_RESPONSE_NODES = 512
MAX_TOOL_RESPONSE_DEPTH = 32
MAX_ASSISTANT_SUMMARY_CHARACTERS = 280
MAX_METADATA_CHARACTERS = 256
MAX_WORKSPACE_CHARACTERS = 4_096
MAX_CHILD_ID_COMPONENT_CHARACTERS = 112
EVENT_LOG_MAX_BYTES = 5 * 1024 * 1024
EVENT_LOG_BACKUP_SUFFIX = ".1"
EVENT_LOG_LOCK_SUFFIX = ".lock"
EVENT_LOG_ERROR_SUFFIX = ".error.json"
EVENT_LOG_LOCK_TIMEOUT_SECONDS = 3.5
EVENT_LOG_LOCK_RETRY_SECONDS = 0.01
STATE_ANCHOR_RETENTION_SECONDS = 7 * 24 * 60 * 60
STATE_EVENT_KINDS = {
    "session_started",
    "prompt_submitted",
    "tool_started",
    "edit_started",
    "tool_succeeded",
    "permission_requested",
    "tool_failed",
    "stopped",
}
SUPPORTED_PROVIDERS = {"codex", "claude", "cursor"}
ATTENTION_NOTIFICATION_TYPES = {
    "permission_prompt",
    "elicitation_dialog",
}
CHILD_EVENT_SPECS = {
    "SubagentStart": ("subagent", ("agent_id", "agentId", "subagent_id", "subagentId")),
    "SubagentStop": ("subagent", ("agent_id", "agentId", "subagent_id", "subagentId")),
    "subagentStart": ("subagent", ("subagent_id", "subagentId", "agent_id", "agentId")),
    "subagentStop": ("subagent", ("subagent_id", "subagentId", "agent_id", "agentId")),
}


def main() -> int:
    try:
        payload = read_payload()
    except (ValueError, json.JSONDecodeError) as error:
        payload = {}
        if not record_delivery_failure(payload, error):
            print(
                f"[CodexPetBar] could not decode local {event_provider(payload)} hook input "
                f"({type(error).__name__}).",
                file=sys.stderr,
            )
        return 0
    event_name = payload.get("hook_event_name")

    try:
        try:
            event = normalize_event(payload)
            if event is not None:
                append_event(event, payload)
                for supplemental_event in supplemental_events(payload, event):
                    append_event(supplemental_event, payload)
        except (OSError, RuntimeError, ValueError) as error:
            # Pet telemetry must never block an agent lifecycle hook.
            if not record_delivery_failure(payload, error):
                provider = event_provider(payload)
                print(
                    f"[CodexPetBar] could not record local {provider} activity "
                    f"({type(error).__name__}).",
                    file=sys.stderr,
                )
    finally:
        if event_name == "Stop":
            print(json.dumps({"continue": True}, separators=(",", ":")))

    return 0


def read_payload() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("hook payload must be a JSON object")
    return value


def normalize_event(payload: dict) -> dict | None:
    provider = event_provider(payload)
    event_name = first_string(payload, "hook_event_name", "hookEventName")
    tool_name = bounded_string(
        first_string(payload, "tool_name", "toolName"),
        MAX_METADATA_CHARACTERS,
    )

    if provider == "cursor":
        kind = cursor_event_kind(event_name, payload, tool_name)
    else:
        kind = claude_compatible_event_kind(event_name, payload, tool_name)

    if kind is None:
        return None

    if provider == "cursor" and event_name in {"subagentStart", "subagentStop"}:
        # Cursor's lifecycle hook exposes an opaque call token here, while the
        # child agent's own events use its real Composer conversation ID. A
        # persistent scope for both identities double-counts one child run.
        # Let the child Composer lifecycle create and close the visible scope.
        return None

    parent_session_id = first_string(
        payload,
        "session_id",
        "sessionId",
        "conversation_id",
        "conversationId",
    )
    child_session_id = scoped_child_session_id(payload, provider, event_name, parent_session_id)
    if event_name in CHILD_EVENT_SPECS and child_session_id is None:
        # A child lifecycle event without its child identifier would overwrite
        # the parent run's state and can make a parallel run disappear.
        return None

    event = {
        "version": 1,
        "timestamp": time.time(),
        "event": kind,
        "hook_event_name": bounded_string(event_name, MAX_METADATA_CHARACTERS),
        "provider": provider,
        "workspace": bounded_string(str(event_root(payload)), MAX_WORKSPACE_CHARACTERS),
    }

    if child_session_id is not None:
        event["session_id"] = child_session_id
        if parent_session_id is not None:
            event["parent_session_id"] = bounded_string(
                parent_session_id,
                MAX_METADATA_CHARACTERS,
            )
    else:
        copy_first_string(
            payload,
            event,
            "session_id",
            "session_id",
            "sessionId",
            "conversation_id",
            "conversationId",
        )
    copy_first_string(
        payload,
        event,
        "turn_id",
        "turn_id",
        "turnId",
        "generation_id",
        "generationId",
        "prompt_id",
        "promptId",
    )
    copy_first_string(
        payload,
        event,
        "tool_name",
        "tool_name",
        "toolName",
        "agent_type",
        "agentType",
        "subagent_type",
        "subagentType",
    )
    copy_first_string(
        payload, event, "tool_use_id", "tool_use_id", "toolUseId", "toolUseID",
        "tool_call_id", "toolCallId", "call_id", "callId",
    )
    copy_first_string(
        payload, event, "permission_request_id", "permission_request_id",
        "permissionRequestId", "request_id", "requestId", "elicitation_id", "elicitationId",
    )
    copy_first_string(payload, event, "permission_mode", "permission_mode", "permissionMode")
    copy_first_string(payload, event, "model", "model", "model_name", "modelName")
    copy_first_string(
        payload,
        event,
        "status",
        "status",
        "final_status",
        "finalStatus",
        "error",
        "reason",
    )
    if event_name == "Notification":
        # Preserve the subtype so readers can distinguish a genuine Claude
        # permission prompt from legacy idle/auth notifications. Older hook
        # versions recorded all three under the same hook event name.
        copy_first_string(
            payload,
            event,
            "status",
            "notification_type",
            "notificationType",
        )

    for prompt_key in ("prompt", "user_prompt", "userPrompt"):
        prompt = payload.get(prompt_key)
        if isinstance(prompt, str):
            event["prompt_length"] = len(prompt)
            break

    summary = terminal_assistant_summary(provider, event_name, payload)
    if summary is not None:
        event["assistant_summary"] = summary

    return event


def event_provider(payload: dict) -> str:
    configured = os.environ.get("CODEX_PET_PROVIDER", "").strip().lower()
    if configured in SUPPORTED_PROVIDERS:
        return configured

    supplied = payload.get("provider")
    if isinstance(supplied, str) and supplied.strip().lower() in SUPPORTED_PROVIDERS:
        return supplied.strip().lower()

    # Existing Codex hooks and older log producers did not identify themselves.
    return "codex"


def claude_compatible_event_kind(
    event_name: str | None,
    payload: dict,
    tool_name: str | None,
) -> str | None:
    if event_name == "PreToolUse":
        return "edit_started" if is_edit_tool(tool_name) else "tool_started"
    if event_name == "PostToolUse":
        return "tool_failed" if tool_event_failed(payload) else "tool_succeeded"
    if event_name in {"PostToolUseFailure", "PermissionDenied", "StopFailure"}:
        return "tool_failed"
    if event_name == "Notification":
        notification_type = first_string(payload, "notification_type", "notificationType")
        return "permission_requested" if notification_type in ATTENTION_NOTIFICATION_TYPES else None

    kind_by_hook = {
        "SessionStart": "session_started",
        "UserPromptSubmit": "prompt_submitted",
        "PermissionRequest": "permission_requested",
        "Elicitation": "permission_requested",
        "ElicitationResult": "tool_succeeded",
        "SubagentStart": "tool_started",
        "SubagentStop": "stopped",
        "CwdChanged": "tool_succeeded",
        "PreCompact": "tool_started",
        "PostCompact": "tool_succeeded",
        "Stop": "stopped",
        "SessionEnd": "stopped",
    }
    return kind_by_hook.get(event_name)


def supplemental_events(payload: dict, event: dict) -> list[dict]:
    """Background shell jobs are not active agent runs."""
    _ = payload, event
    return []


def cursor_event_kind(
    event_name: str | None,
    payload: dict,
    tool_name: str | None,
) -> str | None:
    if event_name == "preToolUse":
        return "edit_started" if is_edit_tool(tool_name) else "tool_started"
    if event_name == "postToolUse":
        return "tool_failed" if tool_event_failed(payload) else "tool_succeeded"
    if event_name == "postToolUseFailure":
        return "tool_failed"
    if event_name == "subagentStop":
        status = first_string(payload, "status")
        if status is not None and status.lower() in {"error", "failed", "failure"}:
            return "tool_failed"
        return "stopped"
    if event_name == "stop":
        status = first_string(payload, "status")
        if status is not None and status.lower() in {"error", "failed", "failure"}:
            return "tool_failed"
        return "stopped"

    return {
        "sessionStart": "session_started",
        "beforeSubmitPrompt": "prompt_submitted",
        "afterAgentResponse": "stopped",
        "subagentStart": "tool_started",
        "preCompact": "tool_started",
        "sessionEnd": "stopped",
    }.get(event_name)


def first_string(payload: dict, *keys: str) -> str | None:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def bounded_string(value: str | None, max_characters: int) -> str | None:
    if value is None or max_characters <= 0:
        return None
    return value if len(value) <= max_characters else value[:max_characters]


def copy_first_string(payload: dict, event: dict, event_key: str, *source_keys: str) -> None:
    value = first_string(payload, *source_keys)
    if value is not None:
        event[event_key] = bounded_string(value, MAX_METADATA_CHARACTERS)


def scoped_child_session_id(
    payload: dict,
    provider: str,
    event_name: str | None,
    parent_session_id: str | None,
) -> str | None:
    spec = CHILD_EVENT_SPECS.get(event_name)
    if spec is None:
        if provider in {"codex", "claude"}:
            spec = ("subagent", ("agent_id", "agentId"))
        elif provider == "cursor":
            spec = ("subagent", ("subagent_id", "subagentId", "agent_id", "agentId"))
        else:
            return None

    scope, source_keys = spec
    child_id = bounded_string(
        first_string(payload, *source_keys),
        MAX_CHILD_ID_COMPONENT_CHARACTERS,
    )
    if child_id is None:
        return None

    parent_id = bounded_string(parent_session_id, MAX_CHILD_ID_COMPONENT_CHARACTERS)
    if parent_id is None:
        return f"{scope}:{child_id}"
    return f"{parent_id}:{scope}:{child_id}"


def terminal_assistant_summary(provider: str, event_name: str | None, payload: dict) -> str | None:
    terminal_events = {
        "codex": {"Stop", "StopFailure", "SubagentStop", "SessionEnd"},
        "claude": {"Stop", "StopFailure", "SubagentStop", "SessionEnd"},
        "cursor": {"afterAgentResponse", "subagentStop", "stop", "sessionEnd"},
    }
    if event_name not in terminal_events[provider]:
        return None

    source_keys = (
        "last_assistant_message",
        "lastAssistantMessage",
        "final_output",
        "finalOutput",
        "assistant_output",
        "assistantOutput",
    )
    if provider == "cursor" and event_name == "afterAgentResponse":
        source_keys = ("text",)
    elif provider == "cursor" and event_name == "subagentStop":
        source_keys = ("summary",) + source_keys

    value = first_string(payload, *source_keys)
    if value is None:
        return None

    summary = " ".join(value.split())
    if not summary:
        return None
    if len(summary) <= MAX_ASSISTANT_SUMMARY_CHARACTERS:
        return summary
    return summary[: MAX_ASSISTANT_SUMMARY_CHARACTERS - 1].rstrip() + "\u2026"


def is_edit_tool(tool_name: object) -> bool:
    return isinstance(tool_name, str) and tool_name.casefold() in {
        "apply_patch",
        "applypatch",
        "create",
        "edit",
        "write",
    }


def tool_failed(response: object) -> bool:
    """Inspect supported result envelopes, never arbitrary returned user data."""
    stack = [(response, 0)]
    seen: set[int] = set()
    visited = 0
    envelope_keys = (
        "tool_response", "toolResponse", "tool_output", "toolOutput",
        "result", "response", "output",
    )
    while stack and visited < MAX_TOOL_RESPONSE_NODES:
        value, depth = stack.pop()
        visited += 1
        if not isinstance(value, (dict, list)) or id(value) in seen:
            continue
        seen.add(id(value))
        if isinstance(value, dict):
            for key in ("exit_code", "exitCode", "returncode", "return_code"):
                code = value.get(key)
                if isinstance(code, int) and not isinstance(code, bool) and code != 0:
                    return True
            # HTTP statuses are not process exit statuses: 200 is success.
            http_status = value.get("status_code")
            if isinstance(http_status, int) and not isinstance(http_status, bool) and http_status >= 400:
                return True
            if value.get("success") is False or value.get("isError") is True or value.get("is_error") is True:
                return True
            status = value.get("status")
            if isinstance(status, str) and status.lower() in {"error", "failed", "failure"}:
                return True
            error = value.get("error")
            if isinstance(error, str):
                if error.strip():
                    return True
            elif error:
                return True
            if depth < MAX_TOOL_RESPONSE_DEPTH:
                stack.extend((value[key], depth + 1) for key in envelope_keys if key in value)
        elif depth < MAX_TOOL_RESPONSE_DEPTH:
            stack.extend((child, depth + 1) for child in value)
    return False


def tool_event_failed(payload: dict) -> bool:
    return tool_failed(payload)


def append_event(event: dict, payload: dict) -> None:
    log_path = event_log_path(payload)
    line = (json.dumps(event, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")
    lock_fd = open_event_lock(log_path)
    try:
        if stat.S_IMODE(os.fstat(lock_fd).st_mode) != 0o600:
            os.fchmod(lock_fd, 0o600)
        acquire_exclusive_lock(lock_fd)
        rotated = rotate_event_log_if_needed(log_path, len(line))
        try:
            append_line(log_path, line)
        except OSError:
            if not rotated or not restore_rotated_log(log_path):
                raise
            append_line(log_path, line)
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)


def record_delivery_failure(payload: dict, error: Exception) -> bool:
    """Persist a metadata-only provider health marker without blocking hooks."""
    provider = event_provider(payload)
    event_name = bounded_string(
        first_string(payload, "hook_event_name", "hookEventName"),
        MAX_METADATA_CHARACTERS,
    )
    marker = {
        "version": 1,
        "timestamp": time.time(),
        "provider": provider,
        "error_type": type(error).__name__,
    }
    if event_name is not None:
        marker["hook_event_name"] = event_name

    log_path = event_log_path(payload)
    for marker_path in delivery_failure_marker_paths(log_path, provider):
        try:
            write_private_json(marker_path, marker)
            return True
        except OSError:
            continue
    return False


def delivery_failure_marker_paths(log_path: Path, provider: str) -> tuple[Path, Path]:
    filename = f"{log_path.name}.{provider}{EVENT_LOG_ERROR_SUFFIX}"
    adjacent = log_path.with_name(filename)
    fallback = Path(tempfile.gettempdir()) / f"codex-pet-bar-hook-{os.getuid()}-{provider}{EVENT_LOG_ERROR_SUFFIX}"
    return adjacent, fallback


def write_private_json(path: Path, value: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temp_fd = -1
    temp_path: Path | None = None
    try:
        temp_fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        temp_path = Path(temp_name)
        os.fchmod(temp_fd, 0o600)
        payload = (json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")
        with os.fdopen(temp_fd, "wb") as handle:
            temp_fd = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
        temp_path = None
        chmod_private(path, 0o600)
    finally:
        if temp_fd != -1:
            os.close(temp_fd)
        if temp_path is not None:
            try:
                temp_path.unlink()
            except OSError:
                pass


def append_line(log_path: Path, line: bytes) -> None:
    fd = open_event_log(log_path)
    try:
        if stat.S_IMODE(os.fstat(fd).st_mode) != 0o600:
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "ab", buffering=0) as handle:
            fd = -1
            # Keep the original log lock as well so upgrades remain compatible
            # with an older installed hook that does not use the sidecar lock.
            acquire_exclusive_lock(handle.fileno())
            handle.write(line)
            fcntl.flock(handle, fcntl.LOCK_UN)
    finally:
        if fd != -1:
            os.close(fd)


def acquire_exclusive_lock(
    file_descriptor: int,
    timeout: float = EVENT_LOG_LOCK_TIMEOUT_SECONDS,
) -> None:
    deadline = time.monotonic() + max(0, timeout)
    while True:
        try:
            fcntl.flock(file_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError as error:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("CodexPetBar event log lock timed out") from error
            time.sleep(min(EVENT_LOG_LOCK_RETRY_SECONDS, remaining))


def rotate_event_log_if_needed(log_path: Path, pending_bytes: int) -> bool:
    try:
        current_bytes = log_path.stat().st_size
    except FileNotFoundError:
        return False
    except OSError:
        return False

    if current_bytes + pending_bytes <= EVENT_LOG_MAX_BYTES:
        return False

    backup_path = Path(f"{log_path}{EVENT_LOG_BACKUP_SUFFIX}")
    try:
        if backup_path.exists():
            retained = retained_rotation_bytes(
                backup_path.read_bytes(),
                log_path.read_bytes(),
                maximum_bytes=EVENT_LOG_MAX_BYTES,
                now_timestamp=time.time(),
            )
            if retained is not None:
                write_private_bytes(backup_path, retained)
                log_path.unlink()
            else:
                os.replace(log_path, backup_path)
        else:
            retained = retained_rotation_bytes(b"", log_path.read_bytes(), EVENT_LOG_MAX_BYTES, time.time())
            if retained is not None:
                write_private_bytes(backup_path, retained)
                log_path.unlink()
            else:
                os.replace(log_path, backup_path)
    except OSError:
        # Rotation is retention hygiene, not a reason to block a Codex hook.
        # The caller will append the submitted event to the active log instead.
        return False
    chmod_private(backup_path, 0o600)
    trim_oversized_backup(backup_path)
    return True


def retained_rotation_bytes(
    previous_backup: bytes,
    active_log: bytes,
    maximum_bytes: int,
    now_timestamp: float,
) -> bytes | None:
    """Persist one replayable lifecycle checkpoint per retained scope."""
    if maximum_bytes <= 0:
        return b""
    grouped: dict[tuple[str, str, str, str], list[dict]] = {}
    valid_event_count = 0
    for line in complete_lines(previous_backup) + complete_lines(active_log):
        try:
            value = json.loads(line)
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(value, dict) or not isinstance(value.get("event"), str):
            continue
        valid_event_count += 1
        timestamp = value.get("timestamp")
        if (value.get("event") not in STATE_EVENT_KINDS
                or isinstance(timestamp, bool) or not isinstance(timestamp, (int, float))):
            continue
        grouped.setdefault(event_scope_key(value), []).append(value)
    if valid_event_count == 0 or not grouped:
        return None

    cutoff = now_timestamp - STATE_ANCHOR_RETENTION_SECONDS
    checkpoints = []
    for values in grouped.values():
        checkpoint = lifecycle_checkpoint(values, retention_cutoff=cutoff, now_timestamp=now_timestamp)
        if checkpoint is not None and checkpoint["timestamp"] >= cutoff:
            checkpoints.append(checkpoint)
    checkpoints.sort(key=lambda event: (event["timestamp"], event_scope_key(event)), reverse=True)
    selected: list[bytes] = []
    selected_bytes = 0
    for checkpoint in checkpoints:
        line = (json.dumps(checkpoint, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")
        if len(line) <= maximum_bytes - selected_bytes:
            selected.append(line)
            selected_bytes += len(line)
    return b"".join(reversed(selected))


def lifecycle_checkpoint(events: list[dict], retention_cutoff: float, now_timestamp: float) -> dict | None:
    """Same state machine/codec as CodexPetLifecycle; covered by Swift replay tests.

    Only reduced metadata is persisted. Raw tool results and prompt text never
    enter the checkpoint. The caller bounds the total serialized checkpoint log.
    """
    state: dict | None = None
    phase: str | None = None
    current_turn: str | None = None
    turn_started_at: float | None = None
    completed_turn: str | None = None
    completed: dict[str, float] = {}
    pending: dict[str, dict] = {}
    for event in sorted(events, key=lambda item: item.get("lifecycle_checkpoint", {}).get("reduced_through") or item["timestamp"]):
        checkpoint = event.get("lifecycle_checkpoint")
        if isinstance(checkpoint, dict) and checkpoint.get("phase") in {
            "listening", "running_established", "running_discovery", "reviewing", "failed", "completed"
        }:
            work_events = checkpoint.get("work_events") or []
            state = work_events[0] if work_events else event
            phase = checkpoint.get("work_phase") or checkpoint["phase"]
            current_turn = checkpoint.get("current_turn_id")
            turn_started_at = checkpoint.get("turn_started_at")
            completed_turn = checkpoint.get("completed_turn_id")
            completed = dict(checkpoint.get("completed_turns", {}))
            pending = {permission_key(item): item for item in checkpoint.get("pending_permissions", [])}
            continue
        provider = event.get("provider", "codex")
        kind = event.get("event")
        hook = event.get("hook_event_name")
        if provider == "claude" and hook == "Notification":
            if (str(event.get("status", "")).strip().lower() not in ATTENTION_NOTIFICATION_TYPES
                    or kind != "permission_requested"):
                continue
        if provider == "cursor" and hook in {"subagentStart", "subagentStop"}:
            continue
        if kind not in STATE_EVENT_KINDS:
            continue
        terminal = lifecycle_terminal(event)
        turn = event.get("turn_id") or None
        if turn in completed and not (terminal and phase == "completed" and completed_turn == turn):
            continue
        if phase == "completed" and not terminal:
            begins_turn = (kind == "session_started"
                or (kind == "prompt_submitted" and (not completed_turn or not turn or turn != completed_turn))
                or (bool(completed_turn) and bool(turn) and turn != completed_turn))
            if not begins_turn:
                continue
            state, phase, current_turn, completed_turn, pending = None, None, turn, None, {}
            turn_started_at = None
        if terminal:
            current_turn = turn or current_turn
            completed_turn = current_turn
            if completed_turn:
                completed[completed_turn] = event["timestamp"]
            pending = {}
            state, phase = event, "completed"
            continue
        if kind in {"session_started", "prompt_submitted"}:
            pending = {}
            current_turn = turn
            turn_started_at = event["timestamp"]
        elif turn:
            if current_turn and current_turn != turn:
                pending = {}
            current_turn = turn
        pending = {key: value for key, value in pending.items()
                   if event["timestamp"] - value["timestamp"] <= 24 * 60 * 60}
        if kind == "session_started":
            state, phase = event, "listening"
        elif kind in {"prompt_submitted", "tool_started", "edit_started"}:
            state, phase = event, "running_established"
        elif kind == "permission_requested":
            pending[permission_key(event)] = without_checkpoint(event)
            if state is None:
                state, phase = event, "reviewing"
        elif kind in {"tool_failed", "tool_succeeded"}:
            resolved_permission = any(resolves_permission(event, value) for value in pending.values())
            pending = {key: value for key, value in pending.items() if not resolves_permission(event, value)}
            if kind == "tool_failed":
                state, phase = event, "failed"
            elif resolved_permission:
                state, phase = event, "running_established"
            else:
                window = {"listening": 90, "running_discovery": 30,
                          "reviewing": 24 * 60 * 60, "failed": 24 * 60 * 60}.get(
                              phase, 6 * 60 * 60 if provider == "codex" else 30 * 60)
                live = state is not None and event["timestamp"] - state["timestamp"] <= window
                phase = "running_established" if live and phase != "running_discovery" else "running_discovery"
                state = event
    if state is None:
        return None
    pending = {key: value for key, value in pending.items() if now_timestamp - value["timestamp"] <= 24 * 60 * 60}
    visible_state = max(pending.values(), key=lambda item: item["timestamp"]) if pending else state
    visible_phase = "reviewing" if pending else phase
    if len(events) == 1 and "lifecycle_checkpoint" not in events[0]:
        return visible_state
    result = without_checkpoint(visible_state)
    workspaces = [event.get("workspace") for event in sorted(events, key=lambda item: item["timestamp"]) if event.get("workspace")]
    if workspaces:
        result["workspace"] = workspaces[0]
    summaries = [candidate for event in events
                 for candidate in [event] + (event.get("lifecycle_checkpoint", {}).get("summary_events") or [])
                 if candidate.get("assistant_summary")]
    result["lifecycle_checkpoint"] = {
        "phase": visible_phase,
        "current_turn_id": current_turn,
        "completed_turn_id": completed_turn,
        "completed_turns": {key: timestamp for key, timestamp in completed.items() if timestamp >= retention_cutoff},
        "pending_permissions": [without_checkpoint(value) for _, value in sorted(pending.items())],
        "work_phase": phase,
        "work_events": [without_checkpoint(state)],
        "summary_events": [without_checkpoint(value) for value in sorted(summaries, key=lambda item: item["timestamp"], reverse=True)[:1]],
        "reduced_through": max(event.get("lifecycle_checkpoint", {}).get("reduced_through") or event["timestamp"] for event in events),
        "turn_started_at": turn_started_at,
    }
    return result


def without_checkpoint(event: dict) -> dict:
    result = dict(event)
    result.pop("lifecycle_checkpoint", None)
    result.setdefault("provider", "codex")
    return result


def lifecycle_terminal(event: dict) -> bool:
    provider = event.get("provider", "codex")
    if event.get("event") == "stopped" or (provider == "claude" and event.get("status") == "background_active"):
        return True
    terminal_hooks = ({"afterAgentResponse", "stop", "sessionEnd"} if provider == "cursor"
                      else {"Stop", "SessionEnd", "SubagentStop"})
    return event.get("hook_event_name") in terminal_hooks


def permission_key(event: dict) -> str:
    if event.get("permission_request_id"):
        return "request:" + event["permission_request_id"]
    if event.get("tool_use_id"):
        return "tool:" + event["tool_use_id"]
    return "uncorrelated:" + (event.get("hook_event_name") or "") + ":" + (event.get("tool_name") or "")


def resolves_permission(event: dict, permission: dict) -> bool:
    for key in ("permission_request_id", "tool_use_id"):
        if permission.get(key) and permission[key] == event.get(key):
            return True
    return (event.get("hook_event_name") == "ElicitationResult"
            and permission.get("hook_event_name") == "Elicitation"
            and not permission.get("permission_request_id") and not permission.get("tool_use_id"))


def complete_lines(data: bytes) -> list[bytes]:
    return [line for line in data.splitlines(keepends=True) if line.endswith(b"\n")]


def event_scope_key(value: dict) -> tuple[str, str, str, str]:
    provider = value.get("provider") if isinstance(value.get("provider"), str) else "codex"
    session_id = value.get("session_id") if isinstance(value.get("session_id"), str) else ""
    if session_id:
        return provider, "", session_id, ""
    workspace = value.get("workspace") if isinstance(value.get("workspace"), str) else ""
    turn_id = value.get("turn_id") if isinstance(value.get("turn_id"), str) else ""
    return provider, workspace, "", turn_id


def write_private_bytes(path: Path, payload: bytes) -> None:
    temp_fd = -1
    temp_path: Path | None = None
    try:
        temp_fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.retain-", dir=path.parent)
        temp_path = Path(temp_name)
        os.fchmod(temp_fd, 0o600)
        with os.fdopen(temp_fd, "wb") as target:
            temp_fd = -1
            target.write(payload)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temp_path, path)
        temp_path = None
        chmod_private(path, 0o600)
    finally:
        if temp_fd != -1:
            os.close(temp_fd)
        if temp_path is not None:
            try:
                temp_path.unlink()
            except OSError:
                pass


def trim_oversized_backup(backup_path: Path) -> bool:
    try:
        backup_size = backup_path.stat().st_size
    except OSError:
        return False
    if backup_size <= EVENT_LOG_MAX_BYTES:
        return False

    start = backup_size - EVENT_LOG_MAX_BYTES
    try:
        with backup_path.open("rb") as source:
            source.seek(start - 1)
            preceding_byte = source.read(1)
            newest_bytes = source.read(EVENT_LOG_MAX_BYTES)
    except OSError:
        return False

    if preceding_byte != b"\n":
        first_line_end = newest_bytes.find(b"\n")
        newest_bytes = b"" if first_line_end < 0 else newest_bytes[first_line_end + 1 :]

    last_line_end = newest_bytes.rfind(b"\n")
    newest_bytes = b"" if last_line_end < 0 else newest_bytes[: last_line_end + 1]

    temp_fd = -1
    temp_path: Path | None = None
    try:
        temp_fd, temp_name = tempfile.mkstemp(
            prefix=f".{backup_path.name}.trim-",
            dir=backup_path.parent,
        )
        temp_path = Path(temp_name)
        os.fchmod(temp_fd, 0o600)
        with os.fdopen(temp_fd, "wb") as target:
            temp_fd = -1
            target.write(newest_bytes)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temp_path, backup_path)
        temp_path = None
        chmod_private(backup_path, 0o600)
        return True
    except OSError:
        return False
    finally:
        if temp_fd != -1:
            os.close(temp_fd)
        if temp_path is not None:
            try:
                temp_path.unlink()
            except OSError:
                pass


def restore_rotated_log(log_path: Path) -> bool:
    backup_path = Path(f"{log_path}{EVENT_LOG_BACKUP_SUFFIX}")
    try:
        if log_path.exists():
            log_path.unlink()
        os.replace(backup_path, log_path)
        chmod_private(log_path, 0o600)
        return True
    except OSError:
        return False


def open_event_lock(log_path: Path) -> int:
    lock_path = Path(f"{log_path}{EVENT_LOG_LOCK_SUFFIX}")
    flags = os.O_RDWR | os.O_CREAT
    try:
        return os.open(lock_path, flags, 0o600)
    except FileNotFoundError:
        ensure_log_parent(log_path.parent)
        return os.open(lock_path, flags, 0o600)


def open_event_log(log_path: Path) -> int:
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    try:
        return os.open(log_path, flags, 0o600)
    except FileNotFoundError:
        ensure_log_parent(log_path.parent)
        return os.open(log_path, flags, 0o600)


def ensure_log_parent(path: Path) -> None:
    try:
        path.mkdir(mode=0o700, parents=True)
    except FileExistsError:
        return
    chmod_private(path, 0o700)


def chmod_private(path: Path, mode: int) -> None:
    try:
        if not path.is_symlink():
            path.chmod(mode)
    except OSError:
        pass


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
    if not isinstance(cwd, str) or not cwd:
        roots = payload.get("workspace_roots", payload.get("workspaceRoots"))
        if isinstance(roots, list):
            cwd = next((root for root in roots if isinstance(root, str) and root), None)
    start = Path(cwd if isinstance(cwd, str) and cwd else os.getcwd()).expanduser()
    return start.resolve()


if __name__ == "__main__":
    raise SystemExit(main())
