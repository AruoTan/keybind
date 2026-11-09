"""Exercise CI download fallback and cache integrity without network access."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]
HELPER = PROJECT / ".devcontainer/scripts/download-verified.sh"


@unittest.skipUnless(shutil.which("bash") and shutil.which("sha256sum"), "Bash download checks")
class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / "cache/tool.zip"
        self.requests = self.root / "requests.txt"
        self.responses = self.root / "responses.json"
        self.primary = "https://fixture.invalid/primary.zip"
        self.fallback = "https://fixture.invalid/fallback.zip"
        self.trusted = "pinned download fixture"
        self.sha256 = hashlib.sha256(self.trusted.encode()).hexdigest()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        curl = bin_dir / "curl"
        curl.write_text(f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
args = sys.argv[1:]
url = args[-1]
with open(os.environ['DOWNLOAD_REQUESTS'], 'a') as output:
    output.write(url + '\\n')
response = json.loads(pathlib.Path(os.environ['DOWNLOAD_RESPONSES']).read_text())[url]
pathlib.Path(args[args.index('--output') + 1]).write_text(response.get('body', ''))
sys.exit(response.get('exit', 0))
''')
        curl.chmod(0o755)
        self.environment = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                            "DOWNLOAD_REQUESTS": str(self.requests), "DOWNLOAD_RESPONSES": str(self.responses)}

    def fetch(self, responses, *urls):
        self.responses.write_text(json.dumps(responses))
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; shift; keybind_download_verified "$@"',
             "download-test", str(HELPER), str(self.destination), self.sha256, *urls],
            env=self.environment, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(list(self.root.rglob("*.partial.*")), [], "Remove partial files on every exit")
        return result

    def requested(self):
        return self.requests.read_text().splitlines() if self.requests.exists() else []

    def test_valid_cache_avoids_all_downloads(self):
        self.destination.parent.mkdir()
        self.destination.write_text(self.trusted)
        result = self.fetch({}, self.primary, self.fallback)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requested(), [])

    def test_http_failure_uses_verified_fallback(self):
        result = self.fetch({self.primary: {"exit": 22, "body": "partial response"},
                             self.fallback: {"body": self.trusted}}, self.primary, self.fallback)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requested(), [self.primary, self.fallback])
        self.assertEqual(self.destination.read_text(), self.trusted)

    def test_bad_response_uses_verified_fallback(self):
        for body in ("<html>gateway error</html>", ""):
            with self.subTest(body=body):
                self.destination.unlink(missing_ok=True)
                result = self.fetch({self.primary: {"body": body}, self.fallback: {"body": self.trusted}},
                                    self.primary, self.fallback)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("SHA256 mismatch", result.stderr)
                self.assertEqual(self.destination.read_text(), self.trusted)

    def test_primary_success_needs_no_fallback(self):
        result = self.fetch({self.primary: {"body": self.trusted}}, self.primary, self.fallback)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requested(), [self.primary])

    def test_single_source_download_still_works(self):
        result = self.fetch({self.primary: {"body": self.trusted}}, self.primary)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destination.read_text(), self.trusted)

    def test_corrupt_cache_is_replaced_only_by_verified_bytes(self):
        self.destination.parent.mkdir()
        self.destination.write_text("corrupt cache")
        result = self.fetch({self.primary: {"body": self.trusted}}, self.primary)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destination.read_text(), self.trusted)

    def test_all_sources_failing_never_publish_unverified_bytes(self):
        result = self.fetch({self.primary: {"exit": 22}, self.fallback: {"body": "wrong bytes"}},
                            self.primary, self.fallback)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No download matched the pinned SHA256", result.stderr)
        self.assertFalse(self.destination.exists())

    def test_failed_download_does_not_overwrite_existing_cache(self):
        self.destination.parent.mkdir()
        self.destination.write_text("existing cache")
        result = self.fetch({self.primary: {"body": "wrong bytes"}}, self.primary)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destination.read_text(), "existing cache")


if __name__ == "__main__":
    unittest.main()
