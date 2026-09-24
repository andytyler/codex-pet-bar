import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "script" / "validate_pet.py"


def load_validator_module():
    spec = importlib.util.spec_from_file_location("validate_pet", VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidatePetTests(unittest.TestCase):
    def test_omitted_version_remains_v1(self):
        validator = load_validator_module()
        with temporary_pet() as pet_directory:
            with mock.patch.object(validator, "image_size", return_value=(1536, 1872)):
                manifest, _ = validator.validate(pet_directory)

        self.assertNotIn("spriteVersionNumber", manifest)

    def test_v2_accepts_eleven_row_atlas(self):
        validator = load_validator_module()
        with temporary_pet(sprite_version=2) as pet_directory:
            with mock.patch.object(validator, "image_size", return_value=(1536, 2288)):
                manifest, _ = validator.validate(pet_directory)

        self.assertEqual(manifest["spriteVersionNumber"], 2)

    def test_v2_rejects_v1_dimensions_with_specific_error(self):
        validator = load_validator_module()
        with temporary_pet(sprite_version=2) as pet_directory:
            with mock.patch.object(validator, "image_size", return_value=(1536, 1872)):
                with self.assertRaisesRegex(
                    validator.ValidationError,
                    "expected 1536x2288 for spriteVersionNumber 2",
                ):
                    validator.validate(pet_directory)

    def test_rejects_unsupported_or_boolean_versions(self):
        validator = load_validator_module()
        for sprite_version in (0, 3, True):
            with self.subTest(sprite_version=sprite_version):
                with temporary_pet(sprite_version=sprite_version) as pet_directory:
                    with self.assertRaisesRegex(
                        validator.ValidationError,
                        "spriteVersionNumber must be 1 or 2",
                    ):
                        validator.validate(pet_directory)


class temporary_pet:
    def __init__(self, sprite_version=None):
        self.sprite_version = sprite_version
        self.temporary_directory = tempfile.TemporaryDirectory()

    def __enter__(self):
        directory = Path(self.temporary_directory.name) / "test-pet"
        directory.mkdir()
        manifest = {
            "id": "test-pet",
            "displayName": "Test Pet",
            "description": "A test pet.",
            "spritesheetPath": "spritesheet.webp",
        }
        if self.sprite_version is not None:
            manifest["spriteVersionNumber"] = self.sprite_version
        (directory / "pet.json").write_text(json.dumps(manifest), encoding="utf-8")
        (directory / "spritesheet.webp").write_bytes(b"RIFF")
        return directory

    def __exit__(self, exc_type, exc_value, traceback):
        self.temporary_directory.cleanup()


if __name__ == "__main__":
    unittest.main()
