import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "script" / "install_hooks.py"


class InstallHooksTests(unittest.TestCase):
    def test_default_install_is_global(self):
        with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as cwd:
            env = os.environ.copy()
            env["CODEX_HOME"] = home

            completed = subprocess.run(
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
            self.assertFalse((Path(cwd) / ".codex" / "hooks.json").exists())

            config = json.loads(hooks_json.read_text(encoding="utf-8"))
            command = config["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
            self.assertIn(f"CODEX_PET_EVENT_LOG={codex_home / 'pet-events.jsonl'}", command)
            self.assertIn(str(hook_script), command)

    def test_workspace_install_remains_available(self):
        with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as workspace:
            env = os.environ.copy()
            env["CODEX_HOME"] = home

            completed = subprocess.run(
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
            self.assertIn(f"CODEX_PET_EVENT_ROOT={workspace_path}", command)
            self.assertIn(str(hook_script), command)


if __name__ == "__main__":
    unittest.main()
