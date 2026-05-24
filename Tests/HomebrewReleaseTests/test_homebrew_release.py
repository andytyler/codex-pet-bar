import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class HomebrewReleaseTests(unittest.TestCase):
    def test_cask_omits_verified_when_url_and_homepage_are_same_domain(self):
        cask = (ROOT / "Casks" / "codex-pet-bar.rb").read_text(encoding="utf-8")

        self.assertIn(
            'url "https://github.com/andytyler/codex-pet-bar/releases/download/v#{version}/CodexPetBar-#{version}-macos.zip"',
            cask,
        )
        self.assertIn(
            'homepage "https://github.com/andytyler/codex-pet-bar"',
            cask,
        )
        self.assertNotIn("verified:", cask)

    def test_release_scripts_audit_cask_by_token_without_new_tap_checks(self):
        for script_name in ("release_homebrew.sh", "publish_homebrew.sh"):
            with self.subTest(script=script_name):
                script = (ROOT / "script" / script_name).read_text(encoding="utf-8")

                self.assertIn('brew audit --cask "$CASK_TOKEN"', script)
                self.assertNotIn("brew audit --cask --new", script)
                self.assertNotIn("brew audit --cask Casks/codex-pet-bar.rb", script)
                self.assertNotIn('brew audit --cask "$TAP_CASK_REL"', script)
                self.assertIn("Tests/HomebrewReleaseTests", script)


if __name__ == "__main__":
    unittest.main()
