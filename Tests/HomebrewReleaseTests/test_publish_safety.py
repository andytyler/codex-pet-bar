import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublishSafetyTests(unittest.TestCase):
    def test_publication_requires_developer_id_and_notarization_before_actions(self):
        result = subprocess.run([str(ROOT / "script/publish_homebrew.sh"), "--version", "1.2.3", "--yes"],
                                env={"PATH": "/usr/bin:/bin", "HOME": "/nonexistent"}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Publishing requires a Developer ID", result.stderr)
        self.assertNotIn("+ git", result.stdout)

    def run_fixture(self, remote_sha="source-sha", change_during_build=False):
        temporary = tempfile.TemporaryDirectory(prefix="pet-publish-safety-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        (root / "script").mkdir()
        (root / "Casks").mkdir()
        tools = root / "tools"
        tools.mkdir()
        shutil.copy2(ROOT / "script/publish_homebrew.sh", root / "script/publish_homebrew.sh")
        shutil.copy2(ROOT / "Casks/codex-pet-bar.rb", root / "Casks/codex-pet-bar.rb")
        original_cask = (root / "Casks/codex-pet-bar.rb").read_bytes()
        helper = root / "script/package_app.sh"
        helper.write_text('''#!/bin/bash
set -eu
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output" ]]; then output="$2"; shift 2; else shift; fi
done
mkdir -p "$output/CodexPetBar.app"
printf '%s\\n' "$output/CodexPetBar.app" >"$output/CodexPetBar-app-path.txt"
printf 'fixture' >"$output/CodexPetBar-$VERSION-macos.zip"
cp "$output/CodexPetBar-$VERSION-macos.zip" "$output/CodexPetBar-macos.zip"
if [[ "$CHANGE_DURING_BUILD" == "1" ]]; then touch "$FIXTURE_ROOT/changed"; fi
''')
        helper.chmod(0o755)
        for name, script in {
            "git": '''#!/bin/bash
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/git-calls"
case "$*" in
  "branch --show-current") echo main ;;
  "rev-parse HEAD") if [[ -f "$FIXTURE_ROOT/changed" ]]; then echo changed-sha; else echo source-sha; fi ;;
  "rev-parse origin/main") echo "$REMOTE_SHA" ;;
  "remote get-url origin") echo https://github.com/andytyler/codex-pet-bar.git ;;
  "show-ref --verify --quiet "*) exit 1 ;;
  "tag --list "*) echo v0.1.2 ;;
  "add "*|"commit "*|"push "*) echo 'unexpected mutation' >&2; exit 91 ;;
esac
''',
            "brew": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FIXTURE_ROOT/brew-calls"\nexit 0\n',
            "swift": "#!/bin/sh\nexit 0\n",
            "python3": "#!/bin/sh\nexit 0\n",
            "gh": "#!/bin/sh\necho 'unexpected GitHub call' >&2\nexit 92\n",
        }.items():
            path = tools / name
            path.write_text(script)
            path.chmod(0o755)
        environment = {"PATH": f"{tools}:/usr/bin:/bin", "HOME": str(root), "TMPDIR": str(root),
                       "FIXTURE_ROOT": str(root), "REMOTE_SHA": remote_sha,
                       "CHANGE_DURING_BUILD": "1" if change_during_build else "0"}
        result = subprocess.run([str(root / "script/publish_homebrew.sh"), "--dry-run", "--output-dir", str(root / "artifacts")],
                                env=environment, text=True, capture_output=True, timeout=30)
        self.assertEqual((root / "Casks/codex-pet-bar.rb").read_bytes(), original_cask)
        return root, result

    def test_dry_run_prepares_cask_without_mutating_source_or_publishing(self):
        root, result = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No commits, pushes, or GitHub release were created", result.stdout)
        self.assertIn('version "0.1.3"', (root / "artifacts/codex-pet-bar.rb").read_text())
        calls = (root / "git-calls").read_text().splitlines()
        self.assertLess(calls.index("fetch origin main --tags"), next(index for index, call in enumerate(calls) if call.startswith("tag --list")))
        self.assertFalse(any(call.startswith(("push", "commit", "add")) for call in calls))
        brew_calls = (root / "brew-calls").read_text().splitlines()
        self.assertEqual(brew_calls, [f"style --cask {root}/artifacts/codex-pet-bar.rb", f"ruby {root}/script/audit_cask.rb {root}/artifacts/codex-pet-bar.rb"])

    def test_remote_source_mismatch_stops_before_build(self):
        root, result = self.run_fixture(remote_sha="other-sha")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Source HEAD must match", result.stderr)
        self.assertFalse((root / "artifacts").exists())

    def test_source_changes_during_preparation_stop_publication(self):
        root, result = self.run_fixture(change_during_build=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Source changed during release preparation", result.stderr)
