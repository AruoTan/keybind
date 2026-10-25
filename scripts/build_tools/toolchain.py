"""Install/check pinned user-owned tools; system packages come from Dockerfile."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import sysconfig
import time
import urllib.request
import zipfile


def load_lock():
    return json.loads((Path(__file__).resolve().parents[1] / "toolchain.json").read_text())


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


def check_system():
    if sys.platform != "linux" or platform.machine() != "x86_64":
        raise RuntimeError("The build environment must be Linux x86_64.")
    for name in ("x86_64-w64-mingw32-gcc", "xvfb-run", "xauth"):
        if not shutil.which(name):
            raise RuntimeError(name + " is missing. Rebuild the devcontainer.")
    wine_binary()
    wine_server()


def check(lock):
    check_system()
    locations = paths(lock)
    for path in locations.values():
        if not path.is_file():
            raise RuntimeError("Missing " + str(path) + "; run python3 scripts/setup_tools.py")
    subprocess.run([str(locations["cargo"]), "+" + lock["rust"]["version"], "--version"], check=True)
    targets = subprocess.check_output([
        str(locations["rustup"]), "target", "list", "--installed", "--toolchain", lock["rust"]["version"]
    ], text=True)
    if lock["rust"]["target"] not in targets.splitlines():
        raise RuntimeError("The pinned Windows Rust target is not installed.")
    print("Pinned Linux/Windows build tools are ready.", flush=True)
    return locations


def install(lock):
    check_system()
    root = tool_root()
    locations = paths(lock)
    for name, output_name in (("autohotkey", "ahk"), ("ahk2exe", "compiler")):
        item = lock[name]
        archive = fetch(item, root / "downloads" / (name + "-" + item["version"] + ".zip"))
        # Re-extract verified inputs; do not trust an edited executable cache.
        unpack(archive, locations[output_name].parent)
    if not locations["rustup"].is_file():
        installer = fetch(lock["rustup"], root / "downloads/rustup-init")
        installer.chmod(0o755)
        subprocess.run([str(installer), "-y", "--profile", "minimal", "--no-modify-path",
                        "--default-toolchain", "none"], check=True)
    subprocess.run([str(locations["rustup"]), "set", "auto-self-update", "disable"], check=True)
    subprocess.run([
        str(locations["rustup"]), "toolchain", "install", lock["rust"]["version"],
        "--profile", "minimal", "--target", lock["rust"]["target"]
    ], check=True)
    # Do not change an existing developer's default toolchain.
    active = subprocess.run([str(locations["rustup"]), "show", "active-toolchain"], capture_output=True)
    if active.returncode:
        subprocess.run([str(locations["rustup"]), "default", lock["rust"]["version"]], check=True)
    check(lock)
