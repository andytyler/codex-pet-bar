import subprocess
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

    def test_publish_script_audits_exact_staged_cask_without_mutating_installed_tap(self):
        script = (ROOT / "script" / "publish_homebrew.sh").read_text(encoding="utf-8")

        self.assertIn("Usage: script/publish_homebrew.sh [options]", script)
        self.assertIn("--bump <patch|minor|major>", script)
        self.assertIn("--sign <identity>", script)
        self.assertIn("--notarize", script)
        self.assertIn("git tag --list 'v[0-9]*.[0-9]*.[0-9]*'", script)
        self.assertIn('gh release create "v$VERSION"', script)
        self.assertIn('run git commit -m "Release codex-pet-bar $VERSION"', script)
        self.assertIn('run git commit -m "Update codex-pet-bar $VERSION"', script)
        self.assertIn('brew ruby "$ROOT_DIR/script/audit_cask.rb" "$STAGED_CASK"', script)
        self.assertIn('brew style --cask "$STAGED_CASK"', script)
        self.assertIn('run cmp "$STAGED_CASK" Casks/codex-pet-bar.rb', script)
        self.assertNotIn('brew audit --cask "$CASK_TOKEN"', script)
        self.assertNotIn("--publish-release", script)
        self.assertNotIn("--push-tap", script)
        self.assertNotIn("--allow-dirty", script)
        self.assertNotIn("brew audit --cask --new", script)
        self.assertNotIn("brew audit --cask Casks/codex-pet-bar.rb", script)
        self.assertNotIn('brew audit --cask "$TAP_CASK_REL"', script)
        self.assertIn("Tests/HomebrewReleaseTests", script)

    def test_publish_script_rejects_non_semver_version_before_prompt(self):
        completed = subprocess.run(
            [str(ROOT / "script" / "publish_homebrew.sh"), "--version", "1.2.3;touch /tmp/codex-pet-pwned"],
            input="",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        self.assertEqual(completed.returncode, 2)
        self.assertIn("VERSION must be strict semver", completed.stderr)
        self.assertNotIn("Releasing CodexPetBar", completed.stdout)

    def test_publish_script_updates_cask_without_shell_interpolating_version_sha(self):
        script = (ROOT / "script" / "publish_homebrew.sh").read_text(encoding="utf-8")

        self.assertIn('run env VERSION="$VERSION" SHA="$SHA" ruby -pi -e', script)
        self.assertNotIn("run_shell \"VERSION='$VERSION' SHA='$SHA' ruby", script)

    def test_cask_uninstall_invokes_safe_global_hook_removal(self):
        cask = (ROOT / "Casks" / "codex-pet-bar.rb").read_text(encoding="utf-8")

        self.assertIn("uninstall script:", cask)
        self.assertIn("codex-pet-install-hooks", cask)
        self.assertIn('"--remove-global"', cask)
        self.assertIn("must_succeed: false", cask)

    def test_release_uploads_stable_latest_download_asset(self):
        package_script = (ROOT / "script" / "package_app.sh").read_text(encoding="utf-8")
        publish_script = (ROOT / "script" / "publish_homebrew.sh").read_text(encoding="utf-8")

        self.assertIn('LATEST_ZIP_PATH="$DIST_DIR/$APP_NAME-macos.zip"', package_script)
        self.assertIn('LATEST_ZIP="$OUTPUT_DIR/CodexPetBar-macos.zip"', publish_script)
        self.assertIn('gh release create "v$VERSION" "$ZIP" "$LATEST_ZIP"', publish_script)

    def test_package_script_supports_developer_id_notarization(self):
        package_script = (ROOT / "script" / "package_app.sh").read_text(encoding="utf-8")
        publish_script = (ROOT / "script" / "publish_homebrew.sh").read_text(encoding="utf-8")

        self.assertIn("--notarize", package_script)
        self.assertIn("--notary-profile <profile>", package_script)
        self.assertIn("xcrun notarytool submit", package_script)
        self.assertIn("xcrun stapler staple", package_script)
        self.assertIn("xcrun stapler validate", package_script)
        self.assertIn('package_args+=(--notarize --notary-profile "$NOTARY_KEYCHAIN_PROFILE" --notary-timeout "$NOTARY_TIMEOUT")', publish_script)

    def test_app_launchers_reuse_the_existing_process(self):
        package_script = (ROOT / "script" / "package_app.sh").read_text(encoding="utf-8")
        install_script = (ROOT / "script" / "install.sh").read_text(encoding="utf-8")

        self.assertIn('exec /usr/bin/open "$APP_DIR"', package_script)
        self.assertIn('/usr/bin/open "$INSTALLED_APP"', install_script)
        self.assertNotIn("/usr/bin/open -n", package_script)
        self.assertNotIn("/usr/bin/open -n", install_script)

    def test_packaged_app_prohibits_multiple_instances(self):
        package_script = (ROOT / "script" / "package_app.sh").read_text(encoding="utf-8")

        self.assertIn(
            "<key>LSMultipleInstancesProhibited</key>\n  <true/>",
            package_script,
        )

    def test_release_is_explicitly_apple_silicon_only(self):
        package_script = (ROOT / "script" / "package_app.sh").read_text(encoding="utf-8")
        run_script = (ROOT / "script" / "build_and_run.sh").read_text(encoding="utf-8")
        cask = (ROOT / "Casks" / "codex-pet-bar.rb").read_text(encoding="utf-8")

        self.assertIn('ARCHITECTURE="${ARCHITECTURE:-arm64}"', package_script)
        self.assertIn('--arch "$ARCHITECTURE" --product "$APP_NAME"', package_script)
        self.assertIn('BUILT_ARCHITECTURES="$(lipo -archs "$APP_BINARY")"', package_script)
        self.assertIn('ARCHITECTURE="arm64"', run_script)
        self.assertIn('swift build --arch "$ARCHITECTURE" --product "$APP_NAME"', run_script)
        self.assertIn('depends_on arch: :arm64', cask)

    def test_development_bundle_copies_swiftpm_resources_and_reuses_the_process(self):
        run_script = (ROOT / "script" / "build_and_run.sh").read_text(encoding="utf-8")

        self.assertIn("-name '*.bundle'", run_script)
        self.assertIn('cp -R "$bundle_path" "$APP_RESOURCES/"', run_script)
        self.assertIn("<key>LSMultipleInstancesProhibited</key>\n  <true/>", run_script)
        self.assertIn('/usr/bin/open "$APP_BUNDLE"', run_script)
        self.assertNotIn('/usr/bin/open -n "$APP_BUNDLE"', run_script)


if __name__ == "__main__":
    unittest.main()
