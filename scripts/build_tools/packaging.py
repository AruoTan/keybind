"""Portable runtime files, source provenance, ZIP and checksums."""
import datetime
import json
import shutil
import zipfile

from . import toolchain as tools
from .common import PROJECT, SOURCE, TESTS, run
from .version import read_version
from .placement import RUNTIME_FILES as PLACEMENT_FILES


def package(lock, stage, locations, dll_details):
    version = read_version()
    files = ["keybind.exe", "VirtualDesktopAccessor.dll", *PLACEMENT_FILES, "verify-virtual-desktop.exe"]
    manifest = {
        "version": version,
        "buildHost": "linux-x86_64", "target": lock["rust"]["target"],
        "builtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "toolchain": lock,
        "rust": run([locations["cargo"], "+" + lock["rust"]["version"], "--version"]),
        "rustup": run([locations["rustup"], "--version"]).splitlines()[0],
        "mingw": run(["x86_64-w64-mingw32-gcc", "--version"]).splitlines()[0],
        "mingw32": run(["i686-w64-mingw32-gcc", "--version"]).splitlines()[0],
        "wine": run([tools.wine_binary(), "--version"]),
        "controllerTests": True, "guidAbiTests": True, "windowDesktopHresultTests": True,
        "compiledStartupSmokeTest": True,
        "compiledNativePlacementStartupSmokeTest": True,
        "rdpHookTests": True, "windowsRdpFullscreenTest": False,
        "rdpFocusHandoffTests": True, "windowsRdpKeyboardAfterSwitchTest": False,
        "continuousDesktopNavigationTests": True, "rememberedDesktopFocusTests": True,
        "dynamicDesktopSwitchTests": True,
        "monitorWorkspaceTests": True, "windowsIndependentMonitorSwitchTest": False,
        "desktopIndicatorTests": True, "windowsDesktopIndicatorTest": False,
        "windowCaptureTests": True, "dwmCloakTests": False,
        "nativePlacementFixtureTests": True, "nativePlacementBridgeTests": True,
        "windowsGlobalPlacementInjectionTest": False, "windowsMixedDpiFirstShowTest": False,
        "windowsWindowTests": False, "nativeQueriesChecked": False, "nativeDesktopOperationsChecked": False,
        "dll": dll_details,
        "artifacts": [{"file": name, "sha256": tools.digest(stage / name)} for name in files],
        "inputs": [{"file": str(path.relative_to(PROJECT)), "sha256": tools.digest(path)}
                   for path in [*sorted(SOURCE.rglob("*.ahk")), *sorted((SOURCE / "native").rglob("*.c")),
                                *sorted((SOURCE / "native").rglob("*.h")), TESTS / "native-check.ahk"]],
    }
    (stage.parent / "keybind-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copy2(PROJECT / "LICENSE", stage / "LICENSE.txt")
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
        f"Keybind {version} Windows x64 portable build\n\n"
        "Extract the whole ZIP. Keep the EXE, DLLs and keybind-placement32.exe together.\n"
        "Exit the old keybind process before starting keybind.exe.\n"
        "Win+Shift+Left/Right moves the active window and follows its desktop.\n"
        "Win+Ctrl+Left/Right switches desktops without moving windows, even from an empty desktop.\n"
        "Both shortcuts create a missing neighbor (left at the beginning) and collect an empty source.\n"
        "With multiple monitors, only the monitor under the pointer changes workspace.\n"
        "Win+Shift requires the active owner window to be on that monitor.\n"
        "Inactive workspace windows stay accessible in a Keybind storage desktop in Task View.\n"
        "Restarting recovers storage after a crash; monitor layout or native desktop changes reset workspaces.\n"
        "New desktop application windows are routed before first show by native x64/x86 hooks.\n"
        "Unsupported, inaccessible or missed windows stay in place; there is no after-show movement.\n"
        "Win+R publishes the pointer monitor before invoking the system Run dialog.\n"
        "Hooks do not elevate processes. Restart affected applications when upgrading native placement DLLs.\n"
        "After cleanup, a click-through card shows the final desktop number for one second.\n"
        "The card does not suppress the native Windows desktop-switch popup.\n"
        "Minimized/hidden source apps are retained; pinned apps stay pinned. Unknown ownership retains the source.\n"
        "In Windows App (msrdc) or mstsc, Win+Ctrl+Left/Right switches LOCAL desktops.\n"
        "Win+Shift+Left/Right moves the LOCAL client window, not a remote app.\n"
        "Keep RDP Windows-key redirection enabled for other Win shortcuts.\n"
        "RDP diagnostics: %LOCALAPPDATA%\\keybind\\remote-desktop.log\n"
        "No Rust, Visual Studio or AutoHotkey installation is needed on Windows.\n\n"
        "Double-click verify.bat for read-only virtual desktop API checks.\n"
        "Run verify.bat --exercise to test real desktop operations with a temporary window.\n"
        "During --exercise, do not manually switch/reorder/create desktops.\n"
        "Linux/Wine tests do not establish compatibility with Windows build 26300.9711.\n"
        "To roll back, exit this build and start your backed-up old keybind.exe.\n",
        encoding="utf-8")
    with zipfile.ZipFile(stage.parent / "keybind-windows-x64.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(stage.iterdir()):
            if path.suffix != ".zip":
                archive.write(path, path.name)
        for item in manifest["inputs"]:
            archive.write(PROJECT / item["file"], "source/" + item["file"])
    checksums = ["windows-x64/" + name for name in files]
    checksums.append("keybind-windows-x64.zip")
    (stage.parent / "SHA256SUMS").write_text("".join(
        tools.digest(stage.parent / name) + "  " + name + "\n" for name in checksums))
