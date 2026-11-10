"""Native first-show routing for both Windows process architectures."""
from .common import PROJECT, run
from .windows import pe_details, windows_path

RUNTIME_FILES = ("KeybindPlacement64.dll", "KeybindPlacement32.dll", "keybind-placement32.exe")


def build(stage, *, test=False):
    source = PROJECT / "src/native/window-placement"
    flags = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-static-libgcc"]
    if test:
        flags += ["-include", PROJECT / "tests/window-placement/virtual-monitors.h"]
    stage.mkdir(parents=True, exist_ok=True)
    for bits, target in ((64, "x86_64"), (32, "i686")):
        dll = stage / f"KeybindPlacement{bits}.dll"
        run([target + "-w64-mingw32-gcc", *flags, "-shared", "-Wl,--kill-at", source / "hook.c",
             "-o", dll, "-ldwmapi"])
        details = pe_details(dll, architecture="x86_64" if bits == 64 else "x86")
        if "comctl32.dll" in {name.lower() for name in details["imports"]}:
            raise RuntimeError("Placement DLL must resolve optional Common Controls functions at runtime: " + str(dll))
        if not {"PlacementStart", "PlacementJoin", "PlacementStop", "PlacementHook", "PlacementBlock",
                "PlacementUpdate", "PlacementStatus", "PlacementAlive"}.issubset(details["exports"]):
            raise RuntimeError("Missing native placement exports: " + str(dll))
    run(["i686-w64-mingw32-gcc", *flags, "-municode", "-mwindows", source / "host.c",
         "-o", stage / RUNTIME_FILES[2]])
    pe_details(stage / RUNTIME_FILES[2], architecture="x86")


def tests(wine, stage):
    build(stage, test=True)
    fixture = PROJECT / "tests/window-placement/native-fixture.c"
    for bits, target in ((64, "x86_64"), (32, "i686")):
        resource = stage / f"fixture-manifest{bits}.o"
        run([target + "-w64-mingw32-windres", "-I", fixture.parent,
             fixture.with_suffix(".rc"), "-o", resource])
        # Test both a host opting into Common Controls v6 and a host without that manifest.
        for name, resources in (("fixture", [resource]), ("legacy", [])):
            run([target + "-w64-mingw32-gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                 "-municode", "-static-libgcc", fixture, *resources,
                 "-o", stage / f"placement-{name}{bits}.exe"])
        for name in ("gate", "subclass"):
            executable = stage / f"placement-{name}{bits}.exe"
            run([target + "-w64-mingw32-gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                 "-municode", "-static-libgcc", PROJECT / f"tests/window-placement/{name}-tests.c",
                 "-o", executable, "-ldwmapi"])
            run([wine.binary, windows_path(executable)], environment=wine.environment,
                timeout=30, log=stage / f"{name}{bits}.log")
    wine.test("pre-show-tests", windows_path(stage), "--local-hook", group="window-placement")
    production = stage.parent / "production"
    build(production)
    wine.test("bridge-tests", windows_path(production), group="window-placement")
