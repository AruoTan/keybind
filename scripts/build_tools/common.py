"""Workspace paths and subprocess execution shared by build steps."""
from pathlib import Path
import subprocess

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "src"
BUILD = PROJECT / "build"
DIST = PROJECT / "dist"
WINDOWS_DIST = DIST / "windows-x64"
LOGS = BUILD / "logs"
TESTS = PROJECT / "tests/virtual-desktop"
TEST_OUTPUT = BUILD / "tests/virtual-desktop"


def run(command, *, environment=None, timeout=120, log=None):
    print("Running: " + " ".join(map(str, command)), flush=True)
    output = None
    if log:
        Path(log).parent.mkdir(parents=True, exist_ok=True)
        output = Path(log).open("w", encoding="utf-8")
    try:
        # File redirection avoids waiting for EOF from Wine's persistent service
        # children after the command itself has exited.
        result = subprocess.run(list(map(str, command)), env=environment, timeout=timeout,
                                stdout=output if output else subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                encoding="utf-8-sig", errors="replace")
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("Process timed out; see " + str(log or command[0])) from error
    finally:
        if output:
            output.close()
    text = Path(log).read_text(encoding="utf-8-sig", errors="replace") if log else result.stdout
    if text:
        print(text.rstrip(), flush=True)
    if result.returncode:
        raise RuntimeError("Command failed (" + str(result.returncode) + "): " + str(command[0]))
    return text.strip()
