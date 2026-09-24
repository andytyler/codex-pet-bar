import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "script"))
import install_pet
import install_hooks


class InstallPetTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.pets = self.root / "codex/pets"
        self.source = self.make_pet(self.root / "source", "new")
        self.destination = self.make_pet(self.pets / "test-pet", "old")
        dimensions = mock.patch("validate_pet.image_size", return_value=(1536, 1872))
        dimensions.start()
        self.addCleanup(dimensions.stop)

    def make_pet(self, path, content):
        path.mkdir(parents=True)
        (path / "pet.json").write_text(json.dumps({"id": "test-pet", "displayName": "Test", "description": "A test", "spritesheetPath": "spritesheet.webp"}))
        (path / "spritesheet.webp").write_text(content)
        return path

    def assert_old_pet(self):
        self.assertEqual((self.destination / "spritesheet.webp").read_text(), "old")
        self.assertEqual(sorted(path.name for path in self.pets.iterdir()), ["test-pet"])

    def test_replaces_existing_pet_after_copy_and_validation(self):
        result = install_pet.install(self.source, self.pets)
        self.assertEqual(result, self.destination)
        self.assertEqual((result / "spritesheet.webp").read_text(), "new")
        self.assertEqual((self.source / "spritesheet.webp").read_text(), "new")
        self.assertEqual(list(self.pets.iterdir()), [self.destination])

    def test_same_path_and_symlink_alias_leave_source_untouched(self):
        alias = self.root / "alias"
        alias.symlink_to(self.destination)
        for source in (self.destination, alias):
            with self.subTest(source=source), self.assertRaises(install_pet.ValidationError):
                install_pet.install(source, self.pets)
            self.assert_old_pet()

    def test_nested_sources_and_destinations_are_rejected(self):
        child = self.make_pet(self.destination / "nested", "nested")
        with self.assertRaises(install_pet.ValidationError):
            install_pet.install(child, self.pets)
        with self.assertRaises(install_pet.ValidationError):
            install_pet.install(self.source, self.source / "nested-pets")
        self.assertEqual((self.destination / "spritesheet.webp").read_text(), "old")
        self.assertEqual((child / "spritesheet.webp").read_text(), "nested")
        self.assertFalse((self.source / "nested-pets").exists())

    def test_failed_copy_preserves_previous_install(self):
        with mock.patch.object(install_pet.shutil, "copytree", side_effect=OSError("copy failed")):
            with self.assertRaisesRegex(OSError, "copy failed"):
                install_pet.install(self.source, self.pets)
        self.assert_old_pet()

    def test_failed_staged_validation_preserves_previous_install(self):
        real_validate = install_pet.validate
        def validate(path):
            if path != self.source:
                raise install_pet.ValidationError("staged copy invalid")
            return real_validate(path)
        with mock.patch.object(install_pet, "validate", side_effect=validate):
            with self.assertRaisesRegex(install_pet.ValidationError, "staged copy invalid"):
                install_pet.install(self.source, self.pets)
        self.assert_old_pet()

    def test_failed_final_rename_restores_previous_install(self):
        rename = os.rename
        def fail_final(source, destination):
            if Path(source).parent.name == "new":
                raise OSError("rename failed")
            return rename(source, destination)
        with mock.patch.object(install_pet.os, "rename", side_effect=fail_final):
            with self.assertRaisesRegex(OSError, "rename failed"):
                install_pet.install(self.source, self.pets)
        self.assert_old_pet()

    def test_destination_symlink_is_rejected_without_touching_target(self):
        shutil.rmtree(self.destination)
        self.destination.symlink_to(self.source)
        with self.assertRaises(install_pet.ValidationError):
            install_pet.install(self.source, self.pets)
        self.assertTrue(self.destination.is_symlink())
        self.assertEqual((self.source / "spritesheet.webp").read_text(), "new")

    def test_codex_home_matches_app_contract(self):
        home = self.root / "home"
        values = {"": home / ".codex", "  ": home / ".codex", "~": home,
                  " ~/custom ": home / "custom", str(self.root / "custom"): self.root / "custom",
                  "relative": Path.cwd() / "relative"}
        for value, expected in values.items():
            with self.subTest(value=value), mock.patch.dict(os.environ, {"HOME": str(home), "CODEX_HOME": value}):
                self.assertEqual(install_hooks.codex_home(), expected.resolve())


class AtomicSettingsTests(unittest.TestCase):
    def test_failed_replace_preserves_existing_provider_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "settings.json"
            config.write_text('{"foreign":true}')
            with mock.patch.object(install_hooks.os, "replace", side_effect=OSError("replace failed")):
                with self.assertRaises(OSError):
                    install_hooks.write_json_config(config, {"updated": True})
            self.assertEqual(json.loads(config.read_text()), {"foreign": True})
            self.assertEqual(list(Path(temporary).iterdir()), [config])

    def test_settings_symlink_and_private_permissions_survive_update(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "settings.json"
            alias = Path(temporary) / "alias.json"
            config.write_text('{}')
            alias.symlink_to(config)
            install_hooks.write_json_config(alias, {"updated": True})
            self.assertTrue(alias.is_symlink())
            self.assertEqual(json.loads(config.read_text()), {"updated": True})
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
