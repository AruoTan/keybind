#!/usr/bin/env bash
# Install container-wide Debian/Ubuntu build dependencies as root.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
    echo "Usage: sudo bash .devcontainer/scripts/install-system.sh" >&2
    exit 2
fi
if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root (or with sudo)." >&2
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    binutils-mingw-w64-x86-64 ca-certificates curl file fonts-dejavu-core \
    gcc-mingw-w64-x86-64-posix jq python3 unzip wine64 xauth xvfb zip
rm -rf /var/lib/apt/lists/*
