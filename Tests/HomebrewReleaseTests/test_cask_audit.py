import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BREW = shutil.which("brew")


@unittest.skipUnless(BREW, "Homebrew is needed to exercise its cask auditor")
class ExactCaskAuditTests(unittest.TestCase):
    def test_audit_reads_the_supplied_version_and_rejects_invalid_staged_content(self):
        with tempfile.TemporaryDirectory(prefix="pet-cask-audit-") as temporary:
            root = Path(temporary).resolve()
            cask = root / "codex-pet-bar.rb"
            source = (ROOT / "Casks/codex-pet-bar.rb").read_text()
            environment = os.environ.copy()
            environment.update({"HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
                                "HOMEBREW_NO_INSTALL_FROM_API": "1", "HOMEBREW_CACHE": str(root / "cache"),
                                "HOMEBREW_TEMP": str(root / "tmp"), "HOMEBREW_LOGS": str(root / "logs")})
            for folder in ("cache", "tmp", "logs"):
                (root / folder).mkdir()
            for version, expected_status in (("9.8.7", 0), ("9:8.7", 1)):
                with self.subTest(version=version):
                    cask.write_text(re.sub(r'version "[^"]+"', f'version "{version}"', source, count=1))
                    completed = subprocess.run([BREW, "ruby", str(ROOT / "script/audit_cask.rb"), str(cask)],
                                               env=environment, text=True, capture_output=True, timeout=45)
                    self.assertEqual(completed.returncode, expected_status, completed.stdout + completed.stderr)
                    self.assertIn(f"Auditing {cask}: version={version}", completed.stdout)
                    if expected_status:
                        self.assertIn("version should not contain colons or slashes", completed.stdout)
