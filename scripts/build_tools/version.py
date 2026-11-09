"""Project release version shared by build and release packaging."""
import os
import re

from .common import PROJECT


def validate_version(version):
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("Version must be a stable major.minor.patch version.")
    if any(int(part) > 65535 for part in version.split(".")):
        raise ValueError("Version components must fit Windows assembly version fields.")
    return version


def read_version():
    version = os.environ.get("KEYBIND_VERSION")
    if version is None:
        version = (PROJECT / "VERSION").read_text().strip()
    return validate_version(version)
