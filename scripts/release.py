#!/usr/bin/env python3
"""Validate release tags and assemble checked Release assets and a Scoop manifest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import zipfile

from build_tools.common import BUILD, DIST, PROJECT
from build_tools.toolchain import digest
from build_tools.version import read_version

RUNTIME_FILES = ("keybind.exe", "VirtualDesktopAccessor.dll")
BUILD_FILES = (*RUNTIME_FILES, "verify-virtual-desktop.exe")
PORTABLE_ZIP = "keybind-windows-x64.zip"
SCOOP_ZIP = "keybind-scoop-x64.zip"
PLUGIN_ZIP = "keybind-keepass-ime.zip"
RELEASE_FILES = (PORTABLE_ZIP, SCOOP_ZIP, PLUGIN_ZIP, "keybind.json", "LICENSE")


def validate_tag(tag):
    version = read_version()
    if tag != "v" + version:
        raise ValueError(f"Release tag must be v{version}, matching VERSION; got {tag!r}.")
    return version


def validate_repository(repository):
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Repository must be a GitHub owner/repo name.")
    return repository


def scoop_manifest(repository, version, sha256):
    homepage = "https://github.com/" + validate_repository(repository)
    return {
        "version": version,
        "description": "Windows hotkeys with active-window-driven virtual desktops",
        "homepage": homepage,
        "license": "GPL-3.0-only",
        "architecture": {"64bit": {
            "url": f"{homepage}/releases/download/v{version}/{SCOOP_ZIP}",
            "hash": sha256,
        }},
        "bin": "keybind.exe",
        "shortcuts": [["keybind.exe", "Keybind"]],
        "notes": [
            "Start Keybind from the Start menu or run keybind. Exit it before updating or uninstalling.",
            "Win+Shift+Left/Right moves the active window and follows its virtual desktop.",
            "The optional KeePass IME plugin is a separate Release download.",
            "Installation does not start Keybind or enable automatic startup.",
        ],
        "checkver": "github",
        "autoupdate": {"architecture": {"64bit": {
            "url": f"{homepage}/releases/download/v$version/{SCOOP_ZIP}",
        }}},
    }


def verify_build(input_dir, version, records_dir):
    windows = input_dir / "windows-x64"
    metadata = json.loads((records_dir / "keybind-build.json").read_text())
    if metadata.get("version") != version:
        raise ValueError("Build version does not match VERSION; run ./build.sh again.")
    records = {item["file"]: item["sha256"] for item in metadata["artifacts"]}
    for name in BUILD_FILES:
        if records.get(name) != digest(windows / name):
            raise ValueError("Build artifact hash mismatch: " + name)
    with zipfile.ZipFile(input_dir / PORTABLE_ZIP) as archive:
        if archive.testzip():
            raise ValueError("Portable ZIP integrity check failed.")
        if "manifest.json" in archive.namelist():
            raise ValueError("Portable ZIP still contains manifest.json; run ./build.sh again.")
        for name in BUILD_FILES:
            if archive.read(name) != (windows / name).read_bytes():
                raise ValueError("Portable ZIP contains a different build: " + name)
    return windows


def verify_plugin(path, version, records_dir):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise ValueError("KeePass ZIP integrity check failed.")
        if set(archive.namelist()) != {"KeybindImeBridge.dll", "README.txt", "LICENSE.txt"}:
            raise ValueError("Unexpected KeePass ZIP contents.")
        metadata = json.loads((records_dir / "keepass-build.json").read_text(encoding="utf-8-sig"))
        if metadata.get("version") != version or metadata.get("pluginLoadTest") is not True:
            raise ValueError("KeePass plugin must match VERSION and pass its loading test.")
        if hashlib.sha256(archive.read("KeybindImeBridge.dll")).hexdigest() != metadata["sha256"].lower():
            raise ValueError("KeePass plugin hash mismatch.")


def write_runtime(windows, stage, repository, version):
    with zipfile.ZipFile(stage / SCOOP_ZIP, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in RUNTIME_FILES:
            archive.write(windows / name, name)
    manifest = scoop_manifest(repository, version, digest(stage / SCOOP_ZIP))
    (stage / "keybind.json").write_text(json.dumps(manifest, indent=4) + "\n")


def write_assets(input_dir, stage, repository, tag, records_dir=None):
    records_dir = records_dir if records_dir is not None else BUILD / "metadata"
    version = validate_tag(tag)
    validate_repository(repository)
    windows = verify_build(input_dir, version, records_dir)
    verify_plugin(input_dir / PLUGIN_ZIP, version, records_dir)
    for name in (PORTABLE_ZIP, PLUGIN_ZIP):
        shutil.copy2(input_dir / name, stage / name)
    shutil.copy2(PROJECT / "LICENSE", stage / "LICENSE")
    write_runtime(windows, stage, repository, version)
    (stage / "SHA256SUMS").write_text("".join(
        digest(stage / name) + "  " + name + "\n" for name in RELEASE_FILES))
    (stage / "release-notes.md").write_text(
        f"Keybind {version}\n\n"
        "- `keybind-windows-x64.zip`: portable application, verifier, licenses and source inputs.\n"
        "- `keybind-scoop-x64.zip`: only keybind.exe and VirtualDesktopAccessor.dll.\n"
        "- `keybind.json`: Scoop manifest with the exact runtime ZIP SHA256.\n"
        "- `keybind-keepass-ime.zip`: optional KeePass plugin; extract into KeePass/Plugins.\n"
        "- `LICENSE` and `SHA256SUMS`: GPL-3.0-only license and release file hashes.\n\n"
        "Install with Scoop (no KeePass dependency):\n\n"
        "```powershell\n"
        f"scoop install https://github.com/{repository}/releases/latest/download/keybind.json\n"
        "```\n\n"
        "Exit any running Keybind before upgrading. Start it manually after installation.\n"
        "Windows build 26300.9711 desktop operations and real IME interactions still require target-machine testing.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate", help="Require a stable tag matching VERSION")
    validate.add_argument("--tag", required=True)
    package = commands.add_parser("package", help="Assemble Release assets from completed builds")
    package.add_argument("--tag", required=True)
    package.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"), required=not os.environ.get("GITHUB_REPOSITORY"))
    package.add_argument("--input-dir", type=Path, default=DIST)
    package.add_argument("--records-dir", type=Path, default=BUILD / "metadata")
    package.add_argument("--output-dir", type=Path, default=DIST / "release")
    args = parser.parse_args()
    if args.command == "validate":
        print(validate_tag(args.tag))
        return
    args.output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".release-stage-", dir=args.output_dir.parent) as temporary:
        stage = Path(temporary)
        write_assets(args.input_dir, stage, args.repository, args.tag, args.records_dir)
        args.output_dir.mkdir(exist_ok=True)
        for path in stage.iterdir():
            path.replace(args.output_dir / path.name)
        (args.output_dir / "manifest.json").unlink(missing_ok=True)
    print("Ready: " + str(args.output_dir))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
