"""Release packaging contracts, without requiring a Windows host or network."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "scripts"))
spec = importlib.util.spec_from_file_location("keybind_release", PROJECT / "scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.input = self.root / "dist"
        self.stage = self.root / "release"
        self.windows = self.input / "windows-x64"
        self.records = self.root / "build/metadata"
        self.records.mkdir(parents=True)
        self.windows.mkdir(parents=True)
        self.stage.mkdir()
        self.version = release.read_version()
        self.tag = "v" + self.version
        for name in release.BUILD_FILES:
            (self.windows / name).write_bytes(("fixture " + name).encode())
        self.build_manifest = {
            "version": self.version,
            "artifacts": [{"file": name, "sha256": release.digest(self.windows / name)}
                          for name in release.BUILD_FILES],
        }
        self.write_build_manifest()
        self.write_portable()
        self.write_plugin()

    def write_build_manifest(self):
        (self.records / "keybind-build.json").write_text(json.dumps(self.build_manifest))

    def write_portable(self):
        with zipfile.ZipFile(self.input / release.PORTABLE_ZIP, "w") as archive:
            for path in self.windows.iterdir():
                archive.write(path, path.name)

    def write_plugin(self, version=None, load_test=True, sha256=None):
        plugin = b"optional KeePass plugin fixture"
        manifest = {
            "version": version or self.version,
            "pluginLoadTest": load_test,
            "sha256": sha256 or hashlib.sha256(plugin).hexdigest(),
        }
        with zipfile.ZipFile(self.input / release.PLUGIN_ZIP, "w") as archive:
            archive.writestr("KeybindImeBridge.dll", plugin)
            # Windows PowerShell 5.1 writes a BOM with Set-Content -Encoding UTF8.
            (self.records / "keepass-build.json").write_bytes(json.dumps(manifest).encode("utf-8-sig"))
            archive.writestr("README.txt", "Optional plugin install instructions")
            archive.writestr("LICENSE.txt", (PROJECT / "LICENSE").read_bytes())

    def package(self):
        release.write_assets(self.input, self.stage, "AruoTan/keybind", self.tag, self.records)

    def test_runtime_contains_only_exe_and_virtual_desktop_dll(self):
        self.package()
        with zipfile.ZipFile(self.stage / release.SCOOP_ZIP) as archive:
            self.assertEqual(set(archive.namelist()), set(release.RUNTIME_FILES))
            for name in release.RUNTIME_FILES:
                self.assertEqual(archive.read(name), (self.windows / name).read_bytes())
        self.assertTrue((self.stage / release.PLUGIN_ZIP).is_file())
        self.assertFalse((self.stage / "manifest.json").exists())
        self.assertTrue((self.stage / "keybind.json").is_file())
        for name in (release.PORTABLE_ZIP, release.SCOOP_ZIP, release.PLUGIN_ZIP):
            with zipfile.ZipFile(self.stage / name) as archive:
                self.assertNotIn("manifest.json", archive.namelist())
                self.assertFalse(any(path.endswith("-build.json") for path in archive.namelist()))

    def test_old_portable_manifest_is_rejected(self):
        with zipfile.ZipFile(self.input / release.PORTABLE_ZIP, "a") as archive:
            archive.writestr("manifest.json", "{}")
        with self.assertRaisesRegex(ValueError, "still contains manifest.json"):
            self.package()

    def test_internal_records_are_required_for_release_validation(self):
        (self.records / "keepass-build.json").unlink()
        with self.assertRaises(FileNotFoundError):
            self.package()

    def test_manifest_has_versioned_url_and_actual_zip_hash(self):
        self.package()
        manifest = json.loads((self.stage / "keybind.json").read_text())
        self.assertEqual(manifest["version"], self.version)
        self.assertEqual(manifest["license"], "GPL-3.0-only")
        arch = manifest["architecture"]
        self.assertEqual(list(arch), ["64bit"])
        self.assertEqual(arch["64bit"]["hash"], release.digest(self.stage / release.SCOOP_ZIP))
        self.assertEqual(arch["64bit"]["url"], f"https://github.com/AruoTan/keybind/releases/download/{self.tag}/{release.SCOOP_ZIP}")
        self.assertEqual(manifest["bin"], "keybind.exe")
        self.assertEqual(manifest["shortcuts"], [["keybind.exe", "Keybind"]])
        for unwanted in ("depends", "suggest", "installer", "post_install", "pre_install", "persist"):
            self.assertNotIn(unwanted, manifest)

    def test_checksums_cover_every_release_asset(self):
        self.package()
        records = {}
        for line in (self.stage / "SHA256SUMS").read_text().splitlines():
            sha256, name = line.split("  ", 1)
            records[name] = sha256
            self.assertEqual(sha256, release.digest(self.stage / name))
        self.assertEqual(set(records), set(release.RELEASE_FILES))

    def test_only_matching_stable_tag_is_allowed(self):
        self.assertEqual(release.validate_tag(self.tag), self.version)
        for tag in (self.version, "v0.0.0", self.tag + "-rc.1", "refs/tags/" + self.tag, "v1.0.0\nmalicious"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_tag(tag)

    def test_repository_is_validated(self):
        for repository in ("https://github.com/AruoTan/keybind", "AruoTan/keybind/extra", "AruoTan/keybind\n", "AruoTan/$(cmd)"):
            with self.subTest(repository=repository), self.assertRaises(ValueError):
                release.validate_repository(repository)

    def test_stale_build_version_is_rejected(self):
        self.build_manifest["version"] = "0.0.0"
        self.write_build_manifest()
        with self.assertRaisesRegex(ValueError, "Build version"):
            self.package()

    def test_modified_binary_is_rejected(self):
        (self.windows / "keybind.exe").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "artifact hash"):
            self.package()

    def test_portable_from_another_build_is_rejected(self):
        with zipfile.ZipFile(self.input / release.PORTABLE_ZIP, "w") as archive:
            for name in release.BUILD_FILES:
                archive.writestr(name, b"other" if name == "keybind.exe" else (self.windows / name).read_bytes())
        with self.assertRaisesRegex(ValueError, "different build"):
            self.package()

    def test_plugin_version_load_test_and_hash_are_required(self):
        for arguments in ({"version": "0.0.0"}, {"load_test": False}, {"sha256": "0" * 64}):
            with self.subTest(arguments=arguments):
                self.write_plugin(**arguments)
                with self.assertRaises(ValueError):
                    self.package()


if __name__ == "__main__":
    unittest.main()
