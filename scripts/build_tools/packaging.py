"""Portable runtime files, source provenance, ZIP and checksums."""
import datetime
import json
import shutil
import zipfile

from . import toolchain as tools
from .common import PROJECT, SOURCE, TESTS, run


def package(lock, stage, locations, dll_details):
    files = ["keybind.exe", "VirtualDesktopAccessor.dll", "verify-virtual-desktop.exe"]
    manifest = {
        "buildHost": "linux-x86_64", "target": lock["rust"]["target"],
        "builtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "toolchain": lock,
        "rust": run([locations["cargo"], "+" + lock["rust"]["version"], "--version"]),
        "rustup": run([locations["rustup"], "--version"]).splitlines()[0],
        "mingw": run(["x86_64-w64-mingw32-gcc", "--version"]).splitlines()[0],
        "wine": run([tools.wine_binary(), "--version"]),
        "controllerTests": True, "guidAbiTests": True, "compiledStartupSmokeTest": True,
        "windowCaptureTests": True, "dwmCloakTests": False,
        "windowsWindowTests": False, "nativeQueriesChecked": False, "nativeDesktopOperationsChecked": False,
        "dll": dll_details,
        "artifacts": [{"file": name, "sha256": tools.digest(stage / name)} for name in files],
        "inputs": [{"file": str(path.relative_to(PROJECT)), "sha256": tools.digest(path)}
                   for path in [*sorted(SOURCE.rglob("*.ahk")), TESTS / "native-check.ahk"]],
    }
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copy2(locations["ahk"].parent / "license.txt", stage / "AutoHotkey.LICENSE.txt")
    # A portable Windows verifier needs no separately installed AHK runtime.
    (stage / "verify.bat").write_bytes((
        '@echo off\nsetlocal\nchcp 65001 >nul\n'
        'set "KEYBIND_VERIFY_LOG=%TEMP%\\keybind-native-check.log"\n'
        'type nul > "%KEYBIND_VERIFY_LOG%"\n'
        'start "" /wait "%~dp0verify-virtual-desktop.exe" "%KEYBIND_VERIFY_LOG%" "%~dp0VirtualDesktopAccessor.dll" %*\n'
        'set "KEYBIND_VERIFY_EXIT=%ERRORLEVEL%"\n'
        'type "%KEYBIND_VERIFY_LOG%"\necho.\npause\nexit /b %KEYBIND_VERIFY_EXIT%\n'
    ).replace("\n", "\r\n").encode("ascii"))
    (stage / "README.txt").write_text(
        "Keybind Windows x64 portable build\n\n"
        "Extract the whole ZIP. Keep both EXE and DLL in the same directory.\n"
        "Exit the old keybind process before starting keybind.exe.\n"
        "Win+Shift+Left/Right moves the active window and follows its desktop.\n"
        "No Rust, Visual Studio or AutoHotkey installation is needed on Windows.\n\n"
        "Double-click verify.bat for read-only virtual desktop API checks.\n"
        "Run verify.bat --exercise to test real desktop operations with a temporary window.\n"
        "During --exercise, do not manually switch/reorder/create desktops.\n"
        "Linux/Wine tests do not establish compatibility with Windows build 26300.9711.\n"
        "manifest.json records the build inputs, binary hashes and tests actually run.\n"
        "To roll back, exit this build and start your backed-up old keybind.exe.\n",
        encoding="utf-8")
    with zipfile.ZipFile(stage.parent / "keybind-windows-x64.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(stage.iterdir()):
            if path.suffix != ".zip":
                archive.write(path, path.name)
        for item in manifest["inputs"]:
            archive.write(PROJECT / item["file"], "source/" + item["file"])
    checksums = ["windows-x64/" + name for name in files + ["manifest.json"]]
    checksums.append("keybind-windows-x64.zip")
    (stage.parent / "SHA256SUMS").write_text("".join(
        tools.digest(stage.parent / name) + "  " + name + "\n" for name in checksums))
