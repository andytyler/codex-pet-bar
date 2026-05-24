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

    def test_only_publish_script_drives_homebrew_releases(self):
        self.assertTrue((ROOT / "script" / "publish_homebrew.sh").is_file())
        self.assertFalse((ROOT / "script" / "release_homebrew.sh").exists())

        markdown_files = [
            path for path in ROOT.rglob("*.md")
            if ".build" not in path.parts
        ]
        for path in markdown_files:
            with self.subTest(path=path.relative_to(ROOT)):
                text = path.read_text(encoding="utf-8")
                self.assertNotIn("release_homebrew.sh", text)

    def test_publish_script_audits_cask_by_token_without_new_tap_checks(self):
        script = (ROOT / "script" / "publish_homebrew.sh").read_text(encoding="utf-8")

        self.assertIn("Usage: script/publish_homebrew.sh [options]", script)
        self.assertIn("--bump <patch|minor|major>", script)
        self.assertIn("git tag --list 'v[0-9]*.[0-9]*.[0-9]*'", script)
        self.assertIn('gh release create "v$VERSION"', script)
        self.assertIn('run git commit -m "Release codex-pet-bar $VERSION"', script)
        self.assertIn('run git commit -m "Update codex-pet-bar $VERSION"', script)
        self.assertIn('brew audit --cask "$CASK_TOKEN"', script)
        self.assertNotIn("--publish-release", script)
        self.assertNotIn("--push-tap", script)
        self.assertNotIn("--allow-dirty", script)
        self.assertNotIn("brew audit --cask --new", script)
        self.assertNotIn("brew audit --cask Casks/codex-pet-bar.rb", script)
        self.assertNotIn('brew audit --cask "$TAP_CASK_REL"', script)
        self.assertIn("Tests/HomebrewReleaseTests", script)


if __name__ == "__main__":
    unittest.main()
