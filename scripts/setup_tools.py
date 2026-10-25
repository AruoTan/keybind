#!/usr/bin/env python3
"""Install or check the pinned user-owned Linux/Windows build tools."""
import argparse
import subprocess
import sys

from build_tools import toolchain


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check tools without installing or downloading")
    arguments = parser.parse_args()
    action = toolchain.check if arguments.check else toolchain.install
    action(toolchain.load_lock())


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
