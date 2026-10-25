"""Project release version shared by build and release packaging."""
import re

from .common import PROJECT


def read_version():
    version = (PROJECT / "VERSION").read_text().strip()
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("VERSION must contain a stable major.minor.patch version.")
    if any(int(part) > 65535 for part in version.split(".")):
        raise ValueError("Version components must fit Windows assembly version fields.")
    return version
