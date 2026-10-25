"""Fail early when the Linux host compiler is absent from a fresh container."""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == 'linux' and platform.machine() == 'x86_64', 'Linux x64 environment check')
class SetupTests(unittest.TestCase):
    def test_missing_host_compiler_is_reported_before_install_or_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            for command in ('dirname', 'uname'):
                Path(temporary, command).symlink_to(shutil.which(command))
            result = subprocess.run(
                ['/bin/bash', str(PROJECT / '.devcontainer/scripts/setup-tools.sh'), '--check'],
                env={**os.environ, 'PATH': temporary}, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('cc is missing', result.stderr)
            self.assertNotIn('Downloading', result.stdout)


if __name__ == '__main__':
    unittest.main()
