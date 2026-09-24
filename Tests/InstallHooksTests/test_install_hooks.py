import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "script" / "install_hooks.py"
UNINSTALLER = ROOT / "script" / "uninstall.sh"


def file_mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def hook_commands(config: dict) -> list[str]:
    commands = []
    for entries in config.get("hooks", {}).values():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            hooks = entry.get("hooks")
            if not isinstance(hooks, list):
                continue
            for hook in hooks:
                if isinstance(hook, dict) and hook.get("type") == "command":
                    commands.append(hook.get("command", ""))
    return commands


def cursor_hook_commands(config: dict) -> list[str]:
    commands = []
    for entries in config.get("hooks", {}).values():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("command"), str):
                commands.append(entry["command"])
    return commands


class InstallHooksTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="pet-installer-tests-")
        self.addCleanup(temporary.cleanup)
        self.sandbox = Path(temporary.name).resolve()
        self.environment = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(self.sandbox / "home"),
            "CODEX_HOME": str(self.sandbox / "home/.codex"),
            "CLAUDE_CONFIG_DIR": str(self.sandbox / "home/.claude"),
            "CURSOR_CONFIG_DIR": str(self.sandbox / "home/.cursor"),
            "INSTALL_DIR": str(self.sandbox / "Applications"),
            "TMPDIR": str(self.sandbox / "tmp"),
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        Path(self.environment["HOME"]).mkdir()
        Path(self.environment["TMPDIR"]).mkdir()

    def run_command(self, *args, **kwargs):
        environment = kwargs.setdefault("env", self.environment)
        for key in ("HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "CURSOR_CONFIG_DIR", "INSTALL_DIR", "TMPDIR"):
            path = Path(environment[key]).resolve()
            self.assertTrue(path == self.sandbox or self.sandbox in path.parents, (key, path))
        return subprocess.run(*args, **kwargs)

    def test_inherited_provider_environment_cannot_escape_test_sandbox(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as foreign:
            sentinel = Path(foreign) / "settings.json"
            sentinel.write_text('{"sentinel": true}\n', encoding="utf-8")
            dangerous = {key: foreign for key in ("HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "CURSOR_CONFIG_DIR")}
            with mock.patch.dict(os.environ, dangerous):
                installed = self.run_command([str(INSTALLER), "--provider", "all"], capture_output=True, text=True)
                self.assertEqual(installed.returncode, 0, installed.stderr)
                removed = self.run_command([str(UNINSTALLER)], capture_output=True, text=True)
                self.assertEqual(removed.returncode, 0, removed.stderr)
            self.assertEqual(list(Path(foreign).iterdir()), [sentinel])
            self.assertEqual(json.loads(sentinel.read_text()), {"sentinel": True})

    def test_provider_all_preserves_foreign_claude_and_cursor_hooks(self):
        with (
            tempfile.TemporaryDirectory(dir=self.sandbox) as codex_home,
            tempfile.TemporaryDirectory(dir=self.sandbox) as claude_home,
            tempfile.TemporaryDirectory(dir=self.sandbox) as cursor_home,
        ):
            claude_settings = Path(claude_home) / "settings.json"
            claude_settings.write_text(
                json.dumps(
                    {
                        "theme": "dark",
                        "hooks": {
                            "Stop": [
                                {
                                    "hooks": [
                                        {"type": "command", "command": "/usr/bin/true # claude foreign"}
                                    ]
                                }
                            ]
                        },
                    }
                ),
                encoding="utf-8",
            )
            cursor_settings = Path(cursor_home) / "hooks.json"
            cursor_settings.write_text(
                json.dumps(
                    {
                        "version": 7,
                        "foreign": {"keep": True},
                        "hooks": {"stop": [{"command": "/usr/bin/true # cursor foreign"}]},
                    }
                ),
                encoding="utf-8",
            )
            env = self.environment.copy()
            env.update(
                {
                    "CODEX_HOME": codex_home,
                    "CLAUDE_CONFIG_DIR": claude_home,
                    "CURSOR_CONFIG_DIR": cursor_home,
                }
            )

            completed = self.run_command(
                [str(INSTALLER), "--provider", "all"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            codex = json.loads((Path(codex_home) / "hooks.json").read_text(encoding="utf-8"))
            claude = json.loads(claude_settings.read_text(encoding="utf-8"))
            cursor = json.loads(cursor_settings.read_text(encoding="utf-8"))
            shared_log = Path(codex_home).resolve() / "pet-events.jsonl"
            codex_commands = hook_commands(codex)
            claude_commands = hook_commands(claude)
            cursor_commands = cursor_hook_commands(cursor)
            self.assertIn("CODEX_PET_PROVIDER=codex", codex_commands[0])
            self.assertTrue(all(f"CODEX_PET_EVENT_LOG={shared_log}" in command for command in codex_commands))
            self.assertEqual(
                set(codex["hooks"]),
                {
                    "SessionStart",
                    "UserPromptSubmit",
                    "PreToolUse",
                    "PermissionRequest",
                    "PostToolUse",
                    "SubagentStart",
                    "SubagentStop",
                    "PreCompact",
                    "PostCompact",
                    "Stop",
                },
            )
            self.assertIn("/usr/bin/true # claude foreign", hook_commands(claude))
            self.assertTrue(any("CODEX_PET_PROVIDER=claude" in command for command in claude_commands))
            self.assertTrue(
                all(
                    f"CODEX_PET_EVENT_LOG={shared_log}" in command
                    for command in claude_commands
                    if "codex_pet_event.py" in command
                )
            )
            self.assertEqual(
                set(claude["hooks"]),
                {
                    "SessionStart",
                    "UserPromptSubmit",
                    "PreToolUse",
                    "PermissionRequest",
                    "PermissionDenied",
                    "PostToolUse",
                    "PostToolUseFailure",
                    "Notification",
                    "Elicitation",
                    "ElicitationResult",
                    "SubagentStart",
                    "SubagentStop",
                    "CwdChanged",
                    "PreCompact",
                    "PostCompact",
                    "Stop",
                    "StopFailure",
                    "SessionEnd",
                },
            )
            self.assertEqual(claude["theme"], "dark")
            self.assertIn("/usr/bin/true # cursor foreign", cursor_commands)
            self.assertTrue(any("CODEX_PET_PROVIDER=cursor" in command for command in cursor_commands))
            self.assertTrue(
                all(
                    f"CODEX_PET_EVENT_LOG={shared_log}" in command
                    for command in cursor_commands
                    if "codex_pet_event.py" in command
                )
            )
            self.assertEqual(cursor["version"], 7)
            self.assertEqual(cursor["foreign"], {"keep": True})
            self.assertEqual(file_mode(Path(codex_home) / "hooks.json"), 0o600)
            self.assertEqual(file_mode(claude_settings), 0o600)
            self.assertEqual(file_mode(cursor_settings), 0o600)
            self.assertNotIn("PermissionRequest", cursor["hooks"])
            self.assertNotIn("permissionRequest", cursor["hooks"])
            pet_claude_commands = {
                command for command in claude_commands if "codex_pet_event.py" in command
            }
            pet_cursor_commands = {
                command for command in cursor_commands if "codex_pet_event.py" in command
            }
            self.assertTrue(pet_claude_commands.isdisjoint(pet_cursor_commands))
            self.assertEqual(
                set(cursor["hooks"]) - {"stop"},
                {
                    "sessionStart",
                    "beforeSubmitPrompt",
                    "preToolUse",
                    "postToolUse",
                    "postToolUseFailure",
                    "afterAgentResponse",
                    "subagentStart",
                    "subagentStop",
                    "preCompact",
                    "sessionEnd",
                },
            )

    def test_reinstall_removes_retired_provider_events_without_touching_foreign_hooks(self):
        with (
            tempfile.TemporaryDirectory(dir=self.sandbox) as codex_home,
            tempfile.TemporaryDirectory(dir=self.sandbox) as claude_home,
            tempfile.TemporaryDirectory(dir=self.sandbox) as cursor_home,
        ):
            env = self.environment.copy()
            env.update(
                {
                    "CODEX_HOME": codex_home,
                    "CLAUDE_CONFIG_DIR": claude_home,
                    "CURSOR_CONFIG_DIR": cursor_home,
                }
            )
            first = self.run_command(
                [str(INSTALLER), "--provider", "all"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(first.returncode, 0, first.stderr)

            claude_path = Path(claude_home) / "settings.json"
            cursor_path = Path(cursor_home) / "hooks.json"
            codex_path = Path(codex_home) / "hooks.json"
            codex = json.loads(codex_path.read_text(encoding="utf-8"))
            claude = json.loads(claude_path.read_text(encoding="utf-8"))
            cursor = json.loads(cursor_path.read_text(encoding="utf-8"))
            codex_command = next(
                command for command in hook_commands(codex) if "CODEX_PET_PROVIDER=codex" in command
            )
            claude_command = next(
                command for command in hook_commands(claude) if "CODEX_PET_PROVIDER=claude" in command
            )
            cursor_command = next(
                command for command in cursor_hook_commands(cursor) if "CODEX_PET_PROVIDER=cursor" in command
            )
            legacy_codex_command = codex_command.replace("CODEX_PET_PROVIDER=codex ", "", 1)
            codex["hooks"]["TaskCreated"] = [
                {"hooks": [{"type": "command", "command": codex_command, "timeout": 5}]},
                {"hooks": [{"type": "command", "command": legacy_codex_command, "timeout": 5}]},
            ]
            claude["hooks"]["TaskCreated"] = [
                {"hooks": [{"type": "command", "command": claude_command, "timeout": 5}]},
                {"hooks": [{"type": "command", "command": "/usr/bin/true # keep claude"}]},
            ]
            cursor["hooks"]["afterAgentThought"] = [
                {"command": cursor_command, "timeout": 5},
                {"command": "/usr/bin/true # keep cursor"},
            ]
            codex_path.write_text(json.dumps(codex), encoding="utf-8")
            claude_path.write_text(json.dumps(claude), encoding="utf-8")
            cursor_path.write_text(json.dumps(cursor), encoding="utf-8")

            second = self.run_command(
                [str(INSTALLER), "--provider", "all"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(second.returncode, 0, second.stderr)

            codex = json.loads(codex_path.read_text(encoding="utf-8"))
            claude = json.loads(claude_path.read_text(encoding="utf-8"))
            cursor = json.loads(cursor_path.read_text(encoding="utf-8"))
            self.assertNotIn("TaskCreated", codex["hooks"])
            self.assertNotIn(claude_command, hook_commands({"hooks": {"TaskCreated": claude["hooks"]["TaskCreated"]}}))
            self.assertIn("/usr/bin/true # keep claude", hook_commands(claude))
            self.assertNotIn(
                cursor_command,
                cursor_hook_commands({"hooks": {"afterAgentThought": cursor["hooks"]["afterAgentThought"]}}),
            )
            self.assertIn("/usr/bin/true # keep cursor", cursor_hook_commands(cursor))

    def test_provider_specific_removal_preserves_foreign_hooks_and_shared_script(self):
        with (
            tempfile.TemporaryDirectory(dir=self.sandbox) as codex_home,
            tempfile.TemporaryDirectory(dir=self.sandbox) as claude_home,
            tempfile.TemporaryDirectory(dir=self.sandbox) as cursor_home,
        ):
            env = self.environment.copy()
            env.update(
                {
                    "CODEX_HOME": codex_home,
                    "CLAUDE_CONFIG_DIR": claude_home,
                    "CURSOR_CONFIG_DIR": cursor_home,
                }
            )
            installed = self.run_command(
                [str(INSTALLER), "--provider", "all"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(installed.returncode, 0, installed.stderr)

            cursor_settings = Path(cursor_home) / "hooks.json"
            cursor = json.loads(cursor_settings.read_text(encoding="utf-8"))
            cursor["hooks"]["stop"].append({"command": "/usr/bin/true # cursor keep"})
            cursor_settings.write_text(json.dumps(cursor), encoding="utf-8")

            claude_settings = Path(claude_home) / "settings.json"
            claude = json.loads(claude_settings.read_text(encoding="utf-8"))
            claude["hooks"]["Stop"].append(
                {"hooks": [{"type": "command", "command": "/usr/bin/true # keep"}]}
            )
            claude_settings.write_text(json.dumps(claude), encoding="utf-8")

            removed = self.run_command(
                [str(INSTALLER), "--provider", "claude", "--remove-global"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(removed.returncode, 0, removed.stderr)
            updated = json.loads(claude_settings.read_text(encoding="utf-8"))
            self.assertEqual(hook_commands(updated), ["/usr/bin/true # keep"])
            self.assertTrue((Path(codex_home) / "hooks" / "codex_pet_event.py").exists())
            cursor = json.loads(cursor_settings.read_text(encoding="utf-8"))
            self.assertTrue(any("CODEX_PET_PROVIDER=cursor" in value for value in cursor_hook_commands(cursor)))

            cursor_removed = self.run_command(
                [str(INSTALLER), "--provider", "cursor", "--remove-global"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(cursor_removed.returncode, 0, cursor_removed.stderr)
            cursor = json.loads(cursor_settings.read_text(encoding="utf-8"))
            self.assertEqual(cursor_hook_commands(cursor), ["/usr/bin/true # cursor keep"])
            self.assertTrue((Path(codex_home) / "hooks" / "codex_pet_event.py").exists())

    def test_non_codex_workspace_provider_is_rejected_without_writing_config(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as workspace:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER), "--provider", "cursor", "--workspace", workspace],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertIn("user-level only", completed.stderr)
            self.assertFalse((Path(workspace) / ".cursor" / "hooks.json").exists())

    def test_default_install_is_global(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as cwd:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER)],
                cwd=cwd,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            codex_home = Path(home).resolve()
            hooks_json = codex_home / "hooks.json"
            hook_script = codex_home / "hooks" / "codex_pet_event.py"

            self.assertTrue(hooks_json.exists())
            self.assertTrue(hook_script.exists())
            self.assertEqual(
                hook_script.read_bytes(),
                (ROOT / ".codex" / "hooks" / "codex_pet_event.py").read_bytes(),
            )
            self.assertFalse((Path(cwd) / ".codex" / "hooks.json").exists())

            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            command = config["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
            self.assertIn(f"CODEX_PET_EVENT_LOG={codex_home / 'pet-events.jsonl'}", command)
            self.assertIn(str(hook_script), command)

    def test_global_install_uses_private_codex_hook_paths(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as cwd:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER)],
                cwd=cwd,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            codex_home = Path(home).resolve()
            hooks_dir = codex_home / "hooks"
            hook_script = hooks_dir / "codex_pet_event.py"

            self.assertEqual(file_mode(codex_home), 0o700)
            self.assertEqual(file_mode(hooks_dir), 0o700)
            self.assertEqual(file_mode(hook_script) & 0o077, 0)

    def test_global_hook_event_log_is_user_only_even_with_permissive_umask(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as cwd:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER)],
                cwd=cwd,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            codex_home = Path(home).resolve()
            hooks_json = codex_home / "hooks.json"
            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            command = config["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]

            previous_umask = os.umask(0o022)
            try:
                hook_run = self.run_command(
                    command,
                    cwd=cwd,
                    input=json.dumps(
                        {
                            "hook_event_name": "UserPromptSubmit",
                            "cwd": str(cwd),
                            "prompt": "hello",
                        }
                    ),
                    shell=True,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
            finally:
                os.umask(previous_umask)

            self.assertEqual(hook_run.returncode, 0, hook_run.stderr)
            self.assertEqual(file_mode(codex_home / "pet-events.jsonl"), 0o600)

    def test_remove_global_hooks_removes_only_codex_pet_entries_and_safe_files(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

            codex_home = Path(home).resolve()
            hooks_json = codex_home / "hooks.json"
            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            foreign_command = "/usr/bin/true # keep me"
            config["hooks"]["UserPromptSubmit"].append(
                {
                    "hooks": [
                        {
                            "type": "command",
                            "command": foreign_command,
                            "timeout": 5,
                        }
                    ]
                }
            )
            hooks_json.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
            empty_log = codex_home / "pet-events.jsonl"
            empty_log.write_text("", encoding="utf-8")

            removed = self.run_command(
                [str(INSTALLER), "--remove-global"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(removed.returncode, 0, removed.stderr)
            updated = json.loads(hooks_json.read_text(encoding="utf-8"))
            commands = hook_commands(updated)
            self.assertFalse(any("codex_pet_event.py" in command for command in commands))
            self.assertIn(foreign_command, commands)
            self.assertFalse((codex_home / "hooks" / "codex_pet_event.py").exists())
            self.assertFalse(empty_log.exists())

    def test_source_uninstall_calls_global_hook_removal(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as install_dir:
            env = self.environment.copy()
            env["HOME"] = home
            env["CODEX_HOME"] = str(Path(home) / ".codex")
            env["INSTALL_DIR"] = install_dir

            installed_app = Path(install_dir) / "CodexPetBar.app"
            installed_app.mkdir()

            completed = self.run_command(
                [str(INSTALLER)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

            uninstall = self.run_command(
                [str(UNINSTALLER)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(uninstall.returncode, 0, uninstall.stderr)
            self.assertFalse(installed_app.exists())
            hooks_json = Path(home).resolve() / ".codex" / "hooks.json"
            updated = json.loads(hooks_json.read_text(encoding="utf-8"))
            self.assertFalse(any("codex_pet_event.py" in command for command in hook_commands(updated)))

    def test_workspace_install_remains_available(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as workspace:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER), "--workspace", workspace],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            workspace_path = Path(workspace).resolve()
            hooks_json = workspace_path / ".codex" / "hooks.json"
            hook_script = workspace_path / ".codex" / "hooks" / "codex_pet_event.py"

            self.assertTrue(hooks_json.exists())
            self.assertTrue(hook_script.exists())
            self.assertFalse((Path(home) / "hooks.json").exists())

            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            command = config["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
            self.assertIn(f"CODEX_PET_EVENT_LOG={Path(home).resolve() / 'pet-events.jsonl'}", command)
            self.assertIn(f"CODEX_PET_EVENT_ROOT={workspace_path}", command)
            self.assertIn(str(hook_script), command)

    def test_workspace_hook_command_writes_global_event_log(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as workspace:
            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER), "--workspace", workspace],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            workspace_path = Path(workspace).resolve()
            codex_home = Path(home).resolve()
            hooks_json = workspace_path / ".codex" / "hooks.json"
            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            command = config["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]

            hook_run = self.run_command(
                command,
                cwd=workspace_path,
                input=json.dumps(
                    {
                        "hook_event_name": "UserPromptSubmit",
                        "cwd": str(workspace_path),
                        "prompt": "hello",
                    }
                ),
                shell=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(hook_run.returncode, 0, hook_run.stderr)
            global_log = codex_home / "pet-events.jsonl"
            workspace_log = workspace_path / ".codex" / "pet-events.jsonl"
            self.assertTrue(global_log.exists())
            self.assertFalse(workspace_log.exists())
            event = json.loads(global_log.read_text(encoding="utf-8").splitlines()[0])
            self.assertEqual(event["workspace"], str(workspace_path))

    def test_git_workspace_hook_command_writes_global_event_log(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as workspace:
            workspace_path = Path(workspace).resolve()
            git_init = self.run_command(
                ["git", "init"],
                cwd=workspace_path,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(git_init.returncode, 0, git_init.stderr)

            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER), "--workspace", workspace],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            codex_home = Path(home).resolve()
            hooks_json = workspace_path / ".codex" / "hooks.json"
            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            command = config["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
            self.assertIn(f"CODEX_PET_EVENT_LOG={codex_home / 'pet-events.jsonl'}", command)
            self.assertIn(f"CODEX_PET_EVENT_ROOT={workspace_path}", command)
            self.assertIn(str(workspace_path / ".codex" / "hooks" / "codex_pet_event.py"), command)
            self.assertNotIn("git rev-parse", command)

            hook_run = self.run_command(
                command,
                cwd=workspace_path,
                input=json.dumps(
                    {
                        "hook_event_name": "UserPromptSubmit",
                        "cwd": str(workspace_path),
                        "prompt": "hello",
                    }
                ),
                shell=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(hook_run.returncode, 0, hook_run.stderr)
            global_log = codex_home / "pet-events.jsonl"
            workspace_log = workspace_path / ".codex" / "pet-events.jsonl"
            self.assertTrue(global_log.exists())
            self.assertFalse(workspace_log.exists())
            event = json.loads(global_log.read_text(encoding="utf-8").splitlines()[0])
            self.assertEqual(event["workspace"], str(workspace_path))

    def test_workspace_reinstall_removes_legacy_workspace_log_command(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as workspace:
            workspace_path = Path(workspace).resolve()
            hooks_json = workspace_path / ".codex" / "hooks.json"
            legacy_script = workspace_path / ".codex" / "hooks" / "codex_pet_event.py"
            legacy_command = f"CODEX_PET_EVENT_ROOT={workspace_path} /usr/bin/python3 {legacy_script}"
            hooks_json.parent.mkdir(parents=True, exist_ok=True)
            hooks_json.write_text(
                json.dumps(
                    {
                        "hooks": {
                            "UserPromptSubmit": [
                                {
                                    "hooks": [
                                        {
                                            "type": "command",
                                            "command": legacy_command,
                                            "timeout": 5,
                                        }
                                    ]
                                }
                            ]
                        }
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER), "--workspace", workspace],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            commands = [
                hook["command"]
                for entry in config["hooks"]["UserPromptSubmit"]
                for hook in entry["hooks"]
            ]
            self.assertNotIn(legacy_command, commands)
            self.assertEqual(1, sum("codex_pet_event.py" in command for command in commands))

    def test_git_workspace_reinstall_removes_legacy_workspace_log_command(self):
        with tempfile.TemporaryDirectory(dir=self.sandbox) as home, tempfile.TemporaryDirectory(dir=self.sandbox) as workspace:
            workspace_path = Path(workspace).resolve()
            git_init = self.run_command(
                ["git", "init"],
                cwd=workspace_path,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(git_init.returncode, 0, git_init.stderr)

            hooks_json = workspace_path / ".codex" / "hooks.json"
            legacy_command = '/usr/bin/python3 "$(git rev-parse --show-toplevel)/.codex/hooks/codex_pet_event.py"'
            hooks_json.parent.mkdir(parents=True, exist_ok=True)
            hooks_json.write_text(
                json.dumps(
                    {
                        "hooks": {
                            "UserPromptSubmit": [
                                {
                                    "hooks": [
                                        {
                                            "type": "command",
                                            "command": legacy_command,
                                            "timeout": 5,
                                        }
                                    ]
                                }
                            ]
                        }
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            env = self.environment.copy()
            env["CODEX_HOME"] = home

            completed = self.run_command(
                [str(INSTALLER), "--workspace", workspace],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            commands = [
                hook["command"]
                for entry in config["hooks"]["UserPromptSubmit"]
                for hook in entry["hooks"]
            ]
            self.assertNotIn(legacy_command, commands)
            self.assertEqual(1, sum("codex_pet_event.py" in command for command in commands))


if __name__ == "__main__":
    unittest.main()
