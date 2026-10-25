#!/usr/bin/env python3
"""Build keybind.exe, VirtualDesktopAccessor.dll and the portable verifier on Linux."""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

from build_tools import toolchain as tools
from build_tools.common import BUILD, DIST, LOGS, SOURCE, TEST_OUTPUT, TESTS, WINDOWS_DIST, run
from build_tools.packaging import package
from build_tools.windows import Wine, pe_details, windows_path


REQUIRED_EXPORTS = {
    "GetDesktopCount", "GetCurrentDesktopNumber", "GetDesktopIdByNumber",
    "GetDesktopNumberById", "GetWindowDesktopId", "IsPinnedWindow", "IsPinnedApp",
    "CreateDesktop", "MoveDesktop", "MoveWindowToDesktopNumber", "GoToDesktopNumber", "RemoveDesktop",
}


def controller_tests(wine):
    tests = TEST_OUTPUT
    tests.mkdir(parents=True, exist_ok=True)
    abi_dll = tests / "guid-abi.dll"
    run(["x86_64-w64-mingw32-gcc", "-shared", "-O2", "-static", "-o", abi_dll,
         TESTS / "guid-abi.c"])
    pe_details(abi_dll)
    wine.test("controller-tests")
    wine.test("guid-abi", windows_path(abi_dll))
    # Execute real window classification/capture. Only DWM cloaking requires
    # native Windows; compiling this test alone misses runtime scope errors.
    wine.test("window-tests", "--skip-dwm")


def build_dll(lock, stage, locations):
    upstream = lock["virtualDesktopAccessor"]
    archive = tools.fetch(upstream, BUILD / "cache" / (upstream["commit"] + ".zip"))
    source = BUILD / "cache/sources" / ("VirtualDesktopAccessor-" + upstream["commit"])
    if source.exists():
        shutil.rmtree(source)
    tools.unpack(archive, BUILD / "cache/sources")
    environment = dict(os.environ)
    # Keep Wine/MinGW development runtimes out of the Windows deployment.
    environment["RUSTFLAGS"] = "-C panic=abort -C target-feature=+crt-static"
    environment["CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER"] = shutil.which("x86_64-w64-mingw32-gcc")
    # Cargo otherwise falls back to Git's proxy, often a Windows localhost
    # address mounted into the devcontainer. Honor explicit container proxies.
    environment.setdefault("CARGO_HTTP_PROXY", next((environment[key] for key in (
        "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"
    ) if environment.get(key)), ""))
    run([locations["cargo"], "+" + lock["rust"]["version"], "build", "--release", "--locked",
         "--target", lock["rust"]["target"], "--target-dir", BUILD / "cache/cargo-target",
         "--package", "dll", "--manifest-path", source / "Cargo.toml"],
        environment=environment, timeout=900, log=LOGS / "cargo.log")
    dll = stage / "VirtualDesktopAccessor.dll"
    shutil.copy2(BUILD / "cache/cargo-target" / lock["rust"]["target"] / "release/VirtualDesktopAccessor.dll", dll)
    details = pe_details(dll)
    if not REQUIRED_EXPORTS.issubset(details["exports"]):
        raise RuntimeError("DLL is missing required exports: " + str(REQUIRED_EXPORTS - set(details["exports"])))
    shutil.copy2(source / "LICENSE.txt", stage / "VirtualDesktopAccessor.LICENSE.txt")
    return details


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-only", action="store_true", help="Run controller, GUID ABI and real window capture tests without packaging")
    arguments = parser.parse_args()
    if not os.environ.get("DISPLAY"):
        raise RuntimeError("Use ./build.sh to provide a headless X display.")
    lock = tools.load_lock()
    locations = tools.check(lock)
    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD / ".linux-build.lock").open("w") as build_lock:
        fcntl.flock(build_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        wine = Wine(locations)
        try:
            wine.boot()
            controller_tests(wine)
            if arguments.test_only:
                return
            with tempfile.TemporaryDirectory(prefix=".linux-stage-", dir=BUILD) as temporary:
                stage = Path(temporary) / "windows-x64"
                stage.mkdir()
                details = build_dll(lock, stage, locations)
                wine.compile(SOURCE / "keybind.ahk", stage / "keybind.exe")
                wine.compile(TESTS / "native-check.ahk", stage / "verify-virtual-desktop.exe")
                with tempfile.TemporaryDirectory(prefix="keybind-startup-") as smoke_dir:
                    smoke_exe = Path(smoke_dir) / "keybind.exe"
                    shutil.copy2(stage / "keybind.exe", smoke_exe)
                    wine.test("startup-smoke", windows_path(smoke_exe))
                package(lock, stage, locations, details)
                # Keep previous published binaries until compilation/tests pass.
                WINDOWS_DIST.mkdir(parents=True, exist_ok=True)
                for artifact in stage.iterdir():
                    artifact.replace(WINDOWS_DIST / artifact.name)
                metadata_dir = BUILD / "metadata"
                metadata_dir.mkdir(parents=True, exist_ok=True)
                (stage.parent / "keybind-build.json").replace(metadata_dir / "keybind-build.json")
                (WINDOWS_DIST / "manifest.json").unlink(missing_ok=True)
                for name in ("keybind-windows-x64.zip", "SHA256SUMS"):
                    (stage.parent / name).replace(DIST / name)
            print("Ready: " + str(DIST / "keybind-windows-x64.zip"), flush=True)
            print("Windows virtual desktop verification is still required; see docs/virtual-desktop.md.", flush=True)
        finally:
            wine.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
