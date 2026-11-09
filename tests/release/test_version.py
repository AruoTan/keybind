"""Release version overrides and local build defaults."""
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "scripts"))
from build_tools.version import read_version


class VersionTests(unittest.TestCase):
    def test_local_build_defaults_to_version_file(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(read_version(), (PROJECT / "VERSION").read_text().strip())

    def test_release_version_overrides_version_file(self):
        with patch.dict(os.environ, {"KEYBIND_VERSION": "2.4.0"}):
            self.assertEqual(read_version(), "2.4.0")

    def test_invalid_override_never_falls_back(self):
        for value in ("", "v2.4.0", "2.4.0-rc.1", "01.2.3", "1.2.65536", "2.4.0\n"):
            with self.subTest(value=value), patch.dict(os.environ, {"KEYBIND_VERSION": value}):
                with self.assertRaises(ValueError):
                    read_version()


if __name__ == "__main__":
    unittest.main()
