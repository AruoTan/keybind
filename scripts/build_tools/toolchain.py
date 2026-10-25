"""Build-side tool locations, downloads and environment validation."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sysconfig
import time
import urllib.request
import zipfile

from .common import PROJECT


def load_lock():
    return json.loads((PROJECT / ".devcontainer/toolchain.json").read_text())


def tool_root():
    return Path(os.environ.get("KEYBIND_TOOLS_DIR", Path.home() / ".local/share/keybind-tools")).resolve()


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def fetch(item, destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and digest(destination) == item["sha256"]:
        return destination
    partial = destination.with_name(destination.name + ".partial")
    for attempt in range(3):
        try:
            print("Downloading " + item["url"], flush=True)
            request = urllib.request.Request(item["url"], headers={"User-Agent": "keybind-build"})
            with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as output:
                shutil.copyfileobj(response, output)
            if digest(partial) != item["sha256"]:
                raise RuntimeError("SHA256 mismatch: " + destination.name)
            partial.replace(destination)
            return destination
        except (OSError, RuntimeError):
            partial.unlink(missing_ok=True)
            if attempt == 2:
                raise
            time.sleep(2)


def unpack(archive, destination):
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive) as bundle:
        for entry in bundle.infolist():
            if not (destination / entry.filename).resolve().is_relative_to(destination):
                raise RuntimeError("Unsafe archive entry: " + entry.filename)
        bundle.extractall(destination)


def paths(lock):
    root = tool_root()
    return {
        "ahk": root / ("autohotkey-" + lock["autohotkey"]["version"]) / "AutoHotkey64.exe",
        "compiler": root / ("ahk2exe-" + lock["ahk2exe"]["version"]) / "Ahk2Exe.exe",
        "cargo": Path.home() / ".cargo/bin/cargo",
        "rustup": Path.home() / ".cargo/bin/rustup",
    }


def wine_binary():
    for candidate in (shutil.which("wine64"), "/usr/lib/wine/wine64", shutil.which("wine")):
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise RuntimeError("Wine is missing. Rebuild the devcontainer.")


def wine_server():
    directory = Path(wine_binary()).resolve().parent
    multiarch_server = Path("/usr/lib") / sysconfig.get_config_var("MULTIARCH") / "wine/wineserver"
    for candidate in (shutil.which("wineserver"), directory / "wineserver", directory / "wineserver64",
                      multiarch_server, "/usr/lib/wine/wineserver64"):
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise RuntimeError("Cannot locate Wine's matching wineserver.")


def check(lock):
    # Keep installation and environment checks in the devcontainer shell entry.
    subprocess.run(["bash", str(PROJECT / ".devcontainer/scripts/setup-tools.sh"), "--check"], check=True)
    return paths(lock)
