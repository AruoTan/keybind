"""PE inspection, Wine execution and AutoHotkey compilation."""
import hashlib
import os
from pathlib import Path
import re
import struct
import subprocess

from . import toolchain as tools
from .common import BUILD, LOGS, PROJECT, TEST_OUTPUT, TESTS, run


def windows_path(path):
    return "Z:" + str(Path(path).resolve()).replace("/", "\\")


def pe_details(path):
    """Read architecture, exports and imports without loading Windows code."""
    data = Path(path).read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[:2] != b"MZ" or data[pe:pe + 4] != b"PE\0\0":
        raise RuntimeError("Not a Windows PE: " + str(path))
    machine, count = struct.unpack_from("<HH", data, pe + 4)
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    if machine != 0x8664 or struct.unpack_from("<H", data, optional)[0] != 0x20B:
        raise RuntimeError("Output is not Windows x64: " + str(path))
    sections = []
    for index in range(count):
        offset = optional + optional_size + index * 40
        virtual_size, rva, size, raw = struct.unpack_from("<IIII", data, offset + 8)
        sections.append((rva, max(size, virtual_size), raw))

    def address(rva):
        for start, size, raw in sections:
            if start <= rva < start + size:
                return raw + rva - start
        raise RuntimeError("Invalid PE RVA: " + str(path))

    def string(rva):
        offset = address(rva)
        return data[offset:data.index(b"\0", offset)].decode("ascii")

    exports, imports = set(), set()
    export_rva = struct.unpack_from("<I", data, optional + 112)[0]
    if export_rva:
        directory = address(export_rva)
        names_count = struct.unpack_from("<I", data, directory + 24)[0]
        names = address(struct.unpack_from("<I", data, directory + 32)[0])
        for index in range(names_count):
            exports.add(string(struct.unpack_from("<I", data, names + index * 4)[0]))
    import_rva = struct.unpack_from("<I", data, optional + 120)[0]
    if import_rva:
        directory = address(import_rva)
        while any(data[directory:directory + 20]):
            imports.add(string(struct.unpack_from("<I", data, directory + 12)[0]))
            directory += 20
    for dependency in imports:
        if re.match(r"(?i)(libgcc|libstdc\+\+|libwinpthread|vcruntime|msvcp)", dependency):
            raise RuntimeError("Unbundled development runtime dependency: " + dependency)
    return {"architecture": "x86_64", "exports": sorted(exports), "imports": sorted(imports)}


class Wine:
    def __init__(self, locations):
        self.locations = locations
        self.binary = tools.wine_binary()
        self.environment = dict(os.environ)
        # Dedicated prefix: never touch a developer's regular Wine applications.
        workspace_key = hashlib.sha256(str(PROJECT).encode()).hexdigest()[:12]
        prefix = Path.home() / ".cache/keybind/wine" / workspace_key
        # Prefixes contain thousands of files: keep them on the container's
        # local filesystem rather than a potentially slow Windows bind mount.
        self.environment.update(WINEPREFIX=str(prefix), WINEARCH="win64", WINEDEBUG="-all",
                                WINEDLLOVERRIDES="mscoree,mshtml=")
        Path(self.environment["WINEPREFIX"]).mkdir(parents=True, exist_ok=True)

    def boot(self):
        run([self.binary, "wineboot.exe", "-u"], environment=self.environment,
            timeout=180, log=LOGS / "wineboot.log")

    def close(self):
        subprocess.run([tools.wine_server(), "-k"], env=self.environment, timeout=10, capture_output=True)

    def test(self, name, *arguments):
        result = TEST_OUTPUT / (name + ".log")
        result.parent.mkdir(parents=True, exist_ok=True)
        result.unlink(missing_ok=True)
        run([self.binary, self.locations["ahk"], "/ErrorStdOut=UTF-8",
             windows_path(TESTS / (name + ".ahk")), windows_path(result), *arguments],
            environment=self.environment, timeout=60, log=result.with_suffix(".stdout.log"))
        if not result.is_file():
            raise RuntimeError("Test did not produce its result: " + name)
        text = result.read_text(encoding="utf-8-sig")
        print(text.rstrip(), flush=True)
        if "FAIL:" in text or "PASS:" not in text:
            raise RuntimeError("Test failed: " + name)

    def compile(self, source, destination):
        run([self.binary, self.locations["compiler"], "/in", windows_path(source),
             "/out", windows_path(destination), "/base", windows_path(self.locations["ahk"]),
             "/compress", "0", "/silent", "verbose"], environment=self.environment,
            timeout=120, log=LOGS / (destination.stem + ".compiler.log"))
        pe_details(destination)
