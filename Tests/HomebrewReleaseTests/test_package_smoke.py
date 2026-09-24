import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PackageSmokeTests(unittest.TestCase):
    def test_generated_bundle_and_relative_output_archive(self):
        with tempfile.TemporaryDirectory(prefix="pet-package-tests-") as temporary:
            root = Path(temporary).resolve()
            build = root / "build"
            build.mkdir()
            binary = build / "CodexPetBar"
            binary.write_text("#!/bin/sh\nexit 0\n")
            binary.chmod(0o755)
            resources = build / "CodexPetBar_CodexPetBarCore.bundle"
            resources.mkdir()
            (resources / "fixture.txt").write_text("fixture")
            tools = root / "tools"
            tools.mkdir()
            for name, text in {
                "swift": '#!/bin/sh\ncase "$*" in *--show-bin-path*) printf "%s\\n" "$FIXTURE_BUILD_DIR";; esac\n',
                "lipo": '#!/bin/sh\nprintf "arm64\\n"\n',
                "codesign": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FIXTURE_SIGN_LOG"\n',
            }.items():
                path = tools / name
                path.write_text(text)
                path.chmod(0o755)
            home = root / "home"
            home.mkdir()
            environment = {"PATH": f"{tools}:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(home),
                           "CODEX_HOME": str(home / ".codex"), "CLAUDE_CONFIG_DIR": str(home / ".claude"),
                           "CURSOR_CONFIG_DIR": str(home / ".cursor"), "TMPDIR": str(root),
                           "FIXTURE_BUILD_DIR": str(build), "FIXTURE_SIGN_LOG": str(root / "sign-calls"), "PYTHONDONTWRITEBYTECODE": "1"}
            package = subprocess.run([str(ROOT / "script/package_app.sh"), "--output", "relative output", "--version", "1.2.3", "--sign", "fixture", "--zip"],
                                     cwd=root, env=environment, text=True, capture_output=True, timeout=90)
            self.assertEqual(package.returncode, 0, package.stderr)
            output = root / "relative output"
            self.assertTrue((output / "CodexPetBar-1.2.3-macos.zip").is_file())
            signing_calls = (root / "sign-calls").read_text().splitlines()
            actual_signing = [call for call in signing_calls if "--force" in call]
            self.assertEqual(len(actual_signing), 1)
            self.assertIn("/private/tmp/codexpetbar-package.", actual_signing[0])
            self.assertNotIn(str(output), actual_signing[0])
            self.assertTrue(any("archive-check/CodexPetBar.app" in call for call in signing_calls))
            self.assertTrue(any(str(output / "CodexPetBar.app") in call and "--verify" in call for call in signing_calls))
            self.assertEqual((output / "CodexPetBar-1.2.3-macos.zip").read_bytes(), (output / "CodexPetBar-macos.zip").read_bytes())
            smoke = subprocess.run(["/usr/bin/python3", str(ROOT / "script/smoke_package.py"), str(output / "CodexPetBar.app")],
                                   env=environment, text=True, capture_output=True, timeout=90)
            self.assertEqual(smoke.returncode, 0, smoke.stderr)
            self.assertIn("Package smoke passed", smoke.stdout)

    def test_cask_uninstall_dispatches_all_providers(self):
        cask = (ROOT / "Casks/codex-pet-bar.rb").read_text()
        arguments = re.search(r"args:\s*(\[[^\]]+\])", cask).group(1)
        self.assertEqual(json.loads(arguments), ["--provider", "all", "--remove-global"])
