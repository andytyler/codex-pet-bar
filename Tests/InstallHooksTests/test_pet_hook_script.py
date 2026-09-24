import importlib.util
import json
import os
import stat
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
HOOK_SCRIPT = ROOT / ".codex" / "hooks" / "codex_pet_event.py"


def load_hook_module():
    spec = importlib.util.spec_from_file_location("codex_pet_event", HOOK_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PetHookScriptTests(unittest.TestCase):
    def test_result_envelopes_distinguish_http_success_empty_error_and_mcp_errors(self):
        hook = load_hook_module()
        fixtures = [
            ({"tool_response": {"error": False}}, False),
            ({"tool_response": {"error": ""}}, False),
            ({"tool_response": {"error": "   "}}, False),
            ({"tool_response": {"error": {}, "status_code": 200}}, False),
            ({"tool_response": {"status_code": 204, "isError": False}}, False),
            ({"tool_response": {"status_code": 404}}, True),
            ({"tool_response": {"exit_code": 1}}, True),
            ({"tool_response": {"exit_code": True}}, False),
            ({"tool_response": {"isError": True, "content": []}}, True),
            ({"tool_response": {"result": {"is_error": True}}}, True),
            ({"tool_response": {"data": {"error": "a field read from a file"}}}, False),
        ]
        for provider, hook_name in [("codex", "PostToolUse"), ("claude", "PostToolUse"), ("cursor", "postToolUse")]:
            with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": provider}):
                for payload, failed in fixtures:
                    with self.subTest(provider=provider, payload=payload):
                        event = hook.normalize_event({"hook_event_name": hook_name, **payload})
                        self.assertEqual(event["event"], "tool_failed" if failed else "tool_succeeded")

    def test_normalized_approvals_retain_tool_and_request_correlation(self):
        hook = load_hook_module()
        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            request = hook.normalize_event({"hook_event_name": "PermissionRequest", "tool_use_id": "tool-1", "request_id": "request-1"})
            completion = hook.normalize_event({"hook_event_name": "PostToolUse", "tool_use_id": "tool-1"})
        self.assertEqual(request["tool_use_id"], completion["tool_use_id"])
        self.assertEqual(request["permission_request_id"], "request-1")
        self.assertNotIn("permission_request_id", completion)

    def test_missing_provider_remains_codex_and_prompt_text_is_not_stored(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {}, clear=True):
            event = hook.normalize_event(
                {
                    "hook_event_name": "UserPromptSubmit",
                    "cwd": "/tmp/project",
                    "session_id": "same-session",
                    "prompt": "do something private",
                }
            )

        self.assertEqual(event["provider"], "codex")
        self.assertEqual(event["event"], "prompt_submitted")
        self.assertEqual(event["prompt_length"], len("do something private"))
        self.assertNotIn("prompt", event)

    def test_claude_failure_and_terminal_events_are_normalized(self):
        hook = load_hook_module()
        fixtures = {
            "PostToolUseFailure": "tool_failed",
            "PermissionDenied": "tool_failed",
            "StopFailure": "tool_failed",
            "SessionEnd": "stopped",
        }

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            for hook_name, expected_kind in fixtures.items():
                with self.subTest(hook_name=hook_name):
                    event = hook.normalize_event(
                        {
                            "hook_event_name": hook_name,
                            "cwd": "/tmp/project",
                            "session_id": "shared-id",
                            "tool_name": "Bash",
                        }
                    )
                    self.assertEqual(event["provider"], "claude")
                    self.assertEqual(event["event"], expected_kind)
                    self.assertEqual(event["session_id"], "shared-id")

    def test_claude_attention_compaction_and_workspace_events_are_normalized(self):
        hook = load_hook_module()
        fixtures = [
            (
                {
                    "hook_event_name": "Notification",
                    "notification_type": "permission_prompt",
                },
                "permission_requested",
            ),
            ({"hook_event_name": "Elicitation"}, "permission_requested"),
            ({"hook_event_name": "ElicitationResult", "action": "accept"}, "tool_succeeded"),
            ({"hook_event_name": "PreCompact"}, "tool_started"),
            ({"hook_event_name": "PostCompact"}, "tool_succeeded"),
            ({"hook_event_name": "CwdChanged"}, "tool_succeeded"),
        ]

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            for payload, expected_kind in fixtures:
                with self.subTest(payload=payload):
                    payload.update({"cwd": "/tmp/project", "session_id": "shared-id"})
                    event = hook.normalize_event(payload)
                    self.assertEqual(event["event"], expected_kind)
                    self.assertEqual(event["session_id"], "shared-id")
                    if payload["hook_event_name"] == "Notification":
                        self.assertEqual(event["status"], "permission_prompt")

            ignored = [
                hook.normalize_event(
                    {
                        "hook_event_name": "Notification",
                        "notification_type": notification_type,
                        "session_id": "shared-id",
                    }
                )
                for notification_type in ("idle_prompt", "auth_success")
            ]

        self.assertEqual(ignored, [None, None])

    def test_claude_stop_ends_agent_turn_even_when_background_work_or_crons_remain(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            background = hook.normalize_event(
                {
                    "hook_event_name": "Stop",
                    "session_id": "parent",
                    "last_assistant_message": "Foreground response finished.",
                    "background_tasks": [
                        {
                            "id": "private-task",
                            "type": "shell",
                            "description": "private description",
                            "command": "private command",
                        }
                    ],
                    "session_crons": [],
                }
            )
            scheduled = hook.normalize_event(
                {
                    "hook_event_name": "Stop",
                    "session_id": "scheduled-parent",
                    "background_tasks": [],
                    "session_crons": [{"id": "cron", "prompt": "private prompt"}],
                }
            )
            finished = hook.normalize_event(
                {
                    "hook_event_name": "Stop",
                    "session_id": "finished-parent",
                    "background_tasks": [],
                    "session_crons": [],
                }
            )

        self.assertEqual(background["event"], "stopped")
        self.assertEqual(background["assistant_summary"], "Foreground response finished.")
        self.assertEqual(scheduled["event"], "stopped")
        self.assertEqual(finished["event"], "stopped")
        for event in (background, scheduled, finished):
            self.assertNotIn("background_tasks", event)
            self.assertNotIn("session_crons", event)
            self.assertNotIn("description", event)
            self.assertNotIn("command", event)
            self.assertNotIn("prompt", event)

    def test_claude_child_events_get_stable_parallel_run_identities(self):
        hook = load_hook_module()
        fixtures = [
            (
                {"hook_event_name": "SubagentStart", "agent_id": "agent-a", "agent_type": "Explore"},
                "tool_started",
                "parent:subagent:agent-a",
            ),
            (
                {
                    "hook_event_name": "SubagentStop",
                    "agent_id": "agent-a",
                    "agent_type": "Explore",
                    "last_assistant_message": "  Found the issue.  ",
                },
                "stopped",
                "parent:subagent:agent-a",
            ),
        ]

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            events = []
            for payload, expected_kind, expected_id in fixtures:
                with self.subTest(payload=payload):
                    payload.update({"cwd": "/tmp/project", "session_id": "parent"})
                    event = hook.normalize_event(payload)
                    self.assertEqual(event["event"], expected_kind)
                    self.assertEqual(event["session_id"], expected_id)
                    self.assertEqual(event["parent_session_id"], "parent")
                    self.assertNotIn("task_subject", event)
                    events.append(event)

            missing_child_id = hook.normalize_event(
                {"hook_event_name": "SubagentStart", "session_id": "parent"}
            )

        self.assertEqual(events[1]["assistant_summary"], "Found the issue.")
        self.assertEqual(events[0]["tool_name"], "Explore")
        self.assertIsNone(missing_child_id)

    def test_claude_todo_and_idle_notifications_do_not_create_run_flags(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            for hook_name in ("TaskCreated", "TaskCompleted", "TeammateIdle"):
                with self.subTest(hook_name=hook_name):
                    event = hook.normalize_event(
                        {
                            "hook_event_name": hook_name,
                            "session_id": "parent",
                            "task_id": "todo-1",
                            "teammate_name": "researcher",
                        }
                    )
                    self.assertIsNone(event)

    def test_codex_subagent_lifecycle_stays_independent_and_keeps_its_summary(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "codex"}):
            started = hook.normalize_event(
                {
                    "hook_event_name": "SubagentStart",
                    "session_id": "parent",
                    "agent_id": "worker-a",
                    "agent_type": "reviewer",
                }
            )
            stopped = hook.normalize_event(
                {
                    "hook_event_name": "SubagentStop",
                    "session_id": "parent",
                    "agent_id": "worker-a",
                    "last_assistant_message": "  Checked every local capture path.  ",
                }
            )

        self.assertEqual(started["event"], "tool_started")
        self.assertEqual(stopped["event"], "stopped")
        self.assertEqual(started["session_id"], "parent:subagent:worker-a")
        self.assertEqual(stopped["session_id"], started["session_id"])
        self.assertEqual(started["parent_session_id"], "parent")
        self.assertEqual(stopped["parent_session_id"], "parent")
        self.assertEqual(stopped["assistant_summary"], "Checked every local capture path.")

    def test_claude_subagent_stop_closes_child_without_promoting_background_shells(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            child = hook.normalize_event(
                {
                    "hook_event_name": "SubagentStop",
                    "session_id": "parent",
                    "agent_id": "worker-a",
                    "last_assistant_message": "Child finished.",
                    "background_tasks": [{"id": "task-1", "command": "private"}],
                }
            )
            supplemental = hook.supplemental_events(
                {
                    "hook_event_name": "SubagentStop",
                    "session_id": "parent",
                    "agent_id": "worker-a",
                    "background_tasks": [{"id": "task-1", "command": "private"}],
                },
                child,
            )

        self.assertEqual(child["event"], "stopped")
        self.assertEqual(child["session_id"], "parent:subagent:worker-a")
        self.assertEqual(supplemental, [])

    def test_claude_subagent_tool_and_attention_events_stay_on_child_identity(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            tool = hook.normalize_event(
                {
                    "hook_event_name": "PreToolUse",
                    "session_id": "parent",
                    "prompt_id": "prompt-1",
                    "agent_id": "agent-a",
                    "agent_type": "Explore",
                    "tool_name": "Bash",
                }
            )
            attention = hook.normalize_event(
                {
                    "hook_event_name": "PermissionRequest",
                    "session_id": "parent",
                    "prompt_id": "prompt-1",
                    "agent_id": "agent-a",
                    "tool_name": "Bash",
                }
            )

        self.assertEqual(tool["event"], "tool_started")
        self.assertEqual(tool["session_id"], "parent:subagent:agent-a")
        self.assertEqual(tool["parent_session_id"], "parent")
        self.assertEqual(tool["turn_id"], "prompt-1")
        self.assertEqual(attention["event"], "permission_requested")
        self.assertEqual(attention["session_id"], "parent:subagent:agent-a")
        self.assertEqual(attention["parent_session_id"], "parent")

    def test_terminal_assistant_summary_is_bounded_and_only_read_from_terminal_events(self):
        hook = load_hook_module()
        assistant_output = "  Finished\n\n" + ("x" * 400)

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            stop = hook.normalize_event(
                {
                    "hook_event_name": "Stop",
                    "last_assistant_message": assistant_output,
                }
            )
            prompt = hook.normalize_event(
                {
                    "hook_event_name": "UserPromptSubmit",
                    "prompt": "private prompt",
                    "last_assistant_message": assistant_output,
                }
            )

        self.assertLessEqual(len(stop["assistant_summary"]), hook.MAX_ASSISTANT_SUMMARY_CHARACTERS)
        self.assertTrue(stop["assistant_summary"].startswith("Finished "))
        self.assertTrue(stop["assistant_summary"].endswith("\u2026"))
        self.assertNotIn("assistant_summary", prompt)
        self.assertNotIn("prompt", prompt)

    def test_cursor_native_events_and_stop_statuses_are_normalized(self):
        hook = load_hook_module()
        fixtures = [
            ({"hook_event_name": "sessionStart"}, "session_started"),
            ({"hook_event_name": "beforeSubmitPrompt", "prompt": "secret"}, "prompt_submitted"),
            ({"hook_event_name": "preToolUse", "tool_name": "edit"}, "edit_started"),
            ({"hook_event_name": "preToolUse", "tool_name": "Shell"}, "tool_started"),
            ({"hook_event_name": "postToolUse"}, "tool_succeeded"),
            ({"hook_event_name": "postToolUseFailure"}, "tool_failed"),
            ({"hook_event_name": "afterAgentResponse", "text": "Finished the change."}, "stopped"),
            ({"hook_event_name": "preCompact"}, "tool_started"),
            ({"hook_event_name": "stop", "status": "completed"}, "stopped"),
            ({"hook_event_name": "stop", "status": "aborted"}, "stopped"),
            ({"hook_event_name": "stop", "status": "error"}, "tool_failed"),
            ({"hook_event_name": "sessionEnd"}, "stopped"),
        ]

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "cursor"}):
            for payload, expected_kind in fixtures:
                with self.subTest(payload=payload):
                    payload.update(
                        {
                            "conversation_id": "shared-id",
                            "generation_id": "turn-a",
                            "workspace_roots": ["/tmp/cursor-project"],
                        }
                    )
                    event = hook.normalize_event(payload)
                    self.assertEqual(event["provider"], "cursor")
                    self.assertEqual(event["event"], expected_kind)
                    self.assertEqual(event["session_id"], "shared-id")
                    self.assertEqual(event["turn_id"], "turn-a")
                    self.assertEqual(event["workspace"], str(Path("/tmp/cursor-project").resolve()))
                    self.assertNotIn("prompt", event)

    def test_cursor_opaque_subagent_lifecycle_does_not_duplicate_child_composer_scope(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "cursor"}):
            started = hook.normalize_event(
                {
                    "hook_event_name": "subagentStart",
                    "conversation_id": "parent",
                    "subagent_id": "worker-1",
                    "subagent_type": "Explore",
                    "task": "private task prompt",
                }
            )
            stopped = hook.normalize_event(
                {
                    "hook_event_name": "subagentStop",
                    "conversation_id": "parent",
                    "subagent_id": "worker-1",
                    "subagent_type": "Explore",
                    "status": "completed",
                    "summary": "  Checked three files. ",
                }
            )
            failed = hook.normalize_event(
                {
                    "hook_event_name": "subagentStop",
                    "conversation_id": "parent",
                    "subagent_id": "worker-2",
                    "status": "error",
                }
            )
            missing_child_id = hook.normalize_event(
                {"hook_event_name": "subagentStart", "conversation_id": "parent"}
            )

        self.assertIsNone(started)
        self.assertIsNone(stopped)
        self.assertIsNone(failed)
        self.assertIsNone(missing_child_id)

    def test_cursor_event_imported_through_claude_config_is_ignored(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            event = hook.normalize_event(
                {
                    "hook_event_name": "preToolUse",
                    "conversation_id": "cursor-session",
                    "cursor_version": "3.11.15",
                }
            )

        self.assertIsNone(event)

    def test_cursor_does_not_treat_permission_request_as_supported(self):
        hook = load_hook_module()

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "cursor"}):
            event = hook.normalize_event({"hook_event_name": "PermissionRequest"})

        self.assertIsNone(event)

    def test_normalized_metadata_is_bounded(self):
        hook = load_hook_module()
        oversized = "x" * (hook.MAX_METADATA_CHARACTERS * 4)

        with mock.patch.dict(os.environ, {"CODEX_PET_PROVIDER": "claude"}):
            event = hook.normalize_event(
                {
                    "hook_event_name": "StopFailure",
                    "session_id": oversized,
                    "model": oversized,
                    "error": oversized,
                }
            )
            child = hook.normalize_event(
                {
                    "hook_event_name": "SubagentStart",
                    "session_id": oversized,
                    "agent_id": oversized,
                }
            )

        self.assertLessEqual(len(event["session_id"]), hook.MAX_METADATA_CHARACTERS)
        self.assertLessEqual(len(event["model"]), hook.MAX_METADATA_CHARACTERS)
        self.assertLessEqual(len(event["status"]), hook.MAX_METADATA_CHARACTERS)
        self.assertLessEqual(len(child["session_id"]), hook.MAX_METADATA_CHARACTERS)

    def test_append_event_skips_parent_and_chmod_work_for_private_existing_log(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            log_path.touch(mode=0o600)
            log_path.chmod(0o600)

            with (
                mock.patch.object(hook, "event_log_path", return_value=log_path),
                mock.patch.object(hook, "ensure_log_parent") as ensure_parent,
                mock.patch.object(hook.os, "fchmod", wraps=os.fchmod) as fchmod,
            ):
                hook.append_event(event, {})

            ensure_parent.assert_not_called()
            fchmod.assert_not_called()
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_append_event_repairs_existing_log_permissions(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            log_path.write_text("", encoding="utf-8")
            log_path.chmod(0o644)

            with mock.patch.object(hook, "event_log_path", return_value=log_path):
                hook.append_event(event, {})

            self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_append_event_creates_private_parent_and_log(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "nested" / "pet-events.jsonl"
            previous_umask = os.umask(0o022)
            try:
                with mock.patch.object(hook, "event_log_path", return_value=log_path):
                    hook.append_event(event, {})
            finally:
                os.umask(previous_umask)

            self.assertEqual(stat.S_IMODE(log_path.parent.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(Path(f"{log_path}.lock").stat().st_mode), 0o600)

    def test_append_event_rotates_before_crossing_five_mib_limit(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            old_log = b"x" * hook.EVENT_LOG_MAX_BYTES
            log_path.write_bytes(old_log)
            log_path.chmod(0o600)

            with mock.patch.object(hook, "event_log_path", return_value=log_path):
                hook.append_event(event, {})

            backup_path = Path(f"{log_path}{hook.EVENT_LOG_BACKUP_SUFFIX}")
            self.assertEqual(backup_path.read_bytes(), old_log)
            self.assertEqual(
                log_path.read_text(encoding="utf-8").splitlines(),
                ['{"event":"prompt_submitted","version":1}'],
            )

    def test_rotation_replaces_the_single_backup_and_keeps_private_permissions(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            backup_path = Path(f"{log_path}{hook.EVENT_LOG_BACKUP_SUFFIX}")
            log_path.write_bytes(b"current")
            log_path.chmod(0o640)
            backup_path.write_bytes(b"obsolete backup")
            backup_path.chmod(0o644)

            with (
                mock.patch.object(hook, "EVENT_LOG_MAX_BYTES", len(b"current")),
                mock.patch.object(hook, "event_log_path", return_value=log_path),
            ):
                hook.append_event(event, {})

            self.assertEqual(backup_path.read_bytes(), b"current")
            self.assertEqual(stat.S_IMODE(backup_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
            self.assertFalse(Path(f"{log_path}.2").exists())

    def test_rotation_caps_an_oversized_legacy_backup_at_complete_newest_lines(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}
        legacy_lines = [
            (f'{{"event":"legacy","index":{index}}}\n').encode("utf-8")
            for index in range(8)
        ]
        newest_lines = b"".join(legacy_lines[-2:])

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            log_path.write_bytes(b"".join(legacy_lines))
            log_path.chmod(0o600)

            with (
                mock.patch.object(hook, "EVENT_LOG_MAX_BYTES", len(newest_lines)),
                mock.patch.object(hook, "event_log_path", return_value=log_path),
            ):
                hook.append_event(event, {})

            backup_path = Path(f"{log_path}{hook.EVENT_LOG_BACKUP_SUFFIX}")
            backup = backup_path.read_bytes()
            self.assertLessEqual(len(backup), len(newest_lines))
            self.assertEqual(backup, newest_lines)
            self.assertTrue(backup.endswith(b"\n"))
            for line in backup.splitlines():
                self.assertEqual(__import__("json").loads(line)["event"], "legacy")
            self.assertEqual(stat.S_IMODE(backup_path.stat().st_mode), 0o600)

    def test_repeated_rotation_carries_quiet_scope_state_through_noisy_history(self):
        hook = load_hook_module()
        quiet = {
            "event": "tool_started",
            "timestamp": 900,
            "provider": "claude",
            "session_id": "quiet-claude",
        }
        previous_lines = [json.dumps(quiet, separators=(",", ":"))]
        previous_lines.extend(
            json.dumps(
                {
                    "event": "tool_succeeded",
                    "timestamp": 901 + index,
                    "provider": "codex",
                    "session_id": "noisy-codex",
                    "index": index,
                },
                separators=(",", ":"),
            )
            for index in range(12)
        )
        active_lines = [
            json.dumps(
                {
                    "event": "tool_started" if index % 2 == 0 else "tool_succeeded",
                    "timestamp": 950 + index,
                    "provider": "codex",
                    "session_id": "noisy-codex",
                    "index": 100 + index,
                },
                separators=(",", ":"),
            )
            for index in range(12)
        ]
        previous = ("\n".join(previous_lines) + "\n").encode("utf-8")
        active = ("\n".join(active_lines) + "\n").encode("utf-8")

        retained = hook.retained_rotation_bytes(
            previous,
            active,
            maximum_bytes=640,
            now_timestamp=1_000,
        )

        self.assertIsNotNone(retained)
        self.assertLessEqual(len(retained), 640)
        events = [json.loads(line) for line in retained.splitlines()]
        self.assertTrue(any(event.get("session_id") == "quiet-claude" for event in events))
        self.assertTrue(
            any(
                event.get("session_id") == "noisy-codex" and event.get("timestamp") == 961
                for event in events
            )
        )

    def test_rotation_failure_falls_back_to_appending_the_new_event(self):
        hook = load_hook_module()
        event = {"event": "prompt_submitted", "version": 1}

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            log_path.write_text("existing\n", encoding="utf-8")

            with (
                mock.patch.object(hook, "EVENT_LOG_MAX_BYTES", 1),
                mock.patch.object(hook, "event_log_path", return_value=log_path),
                mock.patch.object(hook.os, "replace", side_effect=OSError("busy")),
            ):
                hook.append_event(event, {})

            self.assertEqual(
                log_path.read_text(encoding="utf-8").splitlines(),
                ["existing", '{"event":"prompt_submitted","version":1}'],
            )

    def test_concurrent_appenders_rotate_once_without_losing_events(self):
        hook = load_hook_module()

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            old_log = b"x" * 4_096
            log_path.write_bytes(old_log)
            log_path.chmod(0o600)
            hook.EVENT_LOG_MAX_BYTES = log_path.stat().st_size

            def append(index: int) -> None:
                hook.append_event({"event": "tool_succeeded", "index": index, "version": 1}, {})

            with mock.patch.object(hook, "event_log_path", return_value=log_path):
                with ThreadPoolExecutor(max_workers=8) as executor:
                    list(executor.map(append, range(24)))

            backup_path = Path(f"{log_path}{hook.EVENT_LOG_BACKUP_SUFFIX}")
            self.assertEqual(backup_path.read_bytes(), old_log)
            lines = log_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 24)
            self.assertEqual(
                {__import__("json").loads(line)["index"] for line in lines},
                set(range(24)),
            )
            self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(backup_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(Path(f"{log_path}.lock").stat().st_mode), 0o600)

    def test_lock_contention_fails_within_its_own_delivery_timeout(self):
        hook = load_hook_module()

        with tempfile.TemporaryDirectory() as directory:
            lock_path = Path(directory) / "pet-events.jsonl.lock"
            first_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
            second_fd = os.open(lock_path, os.O_RDWR)
            try:
                hook.fcntl.flock(first_fd, hook.fcntl.LOCK_EX | hook.fcntl.LOCK_NB)
                started = hook.time.monotonic()
                with self.assertRaises(TimeoutError):
                    hook.acquire_exclusive_lock(second_fd, timeout=0.03)
                self.assertLess(hook.time.monotonic() - started, 0.5)
            finally:
                hook.fcntl.flock(first_fd, hook.fcntl.LOCK_UN)
                os.close(first_fd)
                os.close(second_fd)

    def test_main_tolerates_event_log_io_errors(self):
        hook = load_hook_module()
        payload = {"hook_event_name": "UserPromptSubmit", "prompt": "hello"}

        with (
            mock.patch.object(hook, "read_payload", return_value=payload),
            mock.patch.object(hook, "append_event", side_effect=OSError("read-only")),
            mock.patch.object(hook, "record_delivery_failure", return_value=True) as record_failure,
        ):
            self.assertEqual(hook.main(), 0)
        record_failure.assert_called_once()

    def test_delivery_failure_marker_is_private_bounded_and_contains_no_payload(self):
        hook = load_hook_module()

        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "pet-events.jsonl"
            payload = {
                "hook_event_name": "UserPromptSubmit",
                "prompt": "private prompt",
                "last_assistant_message": "private output",
            }
            with mock.patch.dict(
                os.environ,
                {
                    "CODEX_PET_PROVIDER": "claude",
                    "CODEX_PET_EVENT_LOG": str(log_path),
                },
            ):
                recorded = hook.record_delivery_failure(payload, PermissionError("private path"))

            marker_path = Path(f"{log_path}.claude{hook.EVENT_LOG_ERROR_SUFFIX}")
            marker = json.loads(marker_path.read_text(encoding="utf-8"))
            self.assertTrue(recorded)
            self.assertEqual(marker["provider"], "claude")
            self.assertEqual(marker["hook_event_name"], "UserPromptSubmit")
            self.assertEqual(marker["error_type"], "PermissionError")
            self.assertNotIn("prompt", marker)
            self.assertNotIn("last_assistant_message", marker)
            self.assertNotIn("private path", marker_path.read_text(encoding="utf-8"))
            self.assertEqual(stat.S_IMODE(marker_path.stat().st_mode), 0o600)

    def test_malformed_hook_input_records_failure_without_blocking(self):
        hook = load_hook_module()

        with (
            mock.patch.object(hook, "read_payload", side_effect=json.JSONDecodeError("bad", "{", 1)),
            mock.patch.object(hook, "record_delivery_failure", return_value=True) as record_failure,
        ):
            self.assertEqual(hook.main(), 0)
        record_failure.assert_called_once()

    def test_tool_failed_handles_deep_payload_without_recursion_error(self):
        hook = load_hook_module()
        payload = {}
        cursor = payload
        for _ in range(2_000):
            child = {}
            cursor["child"] = child
            cursor = child

        self.assertFalse(hook.tool_failed(payload))

    def test_tool_failed_still_detects_shallow_failures(self):
        hook = load_hook_module()

        self.assertTrue(hook.tool_failed({"tool_response": [{"success": False}]}))

    def test_post_tool_failure_detection_does_not_scan_private_tool_input(self):
        hook = load_hook_module()

        self.assertFalse(
            hook.tool_event_failed(
                {
                    "tool_input": {"error": "a user-supplied field, not an execution error"},
                    "tool_response": {"success": True},
                }
            )
        )
        self.assertTrue(hook.tool_event_failed({"status": "error"}))
        self.assertTrue(hook.tool_event_failed({"tool_output": {"exit_code": 1}}))


if __name__ == "__main__":
    unittest.main()
