#!/usr/bin/env bash
# Install/check pinned user-owned tools; no sudo or project build is performed.
set -euo pipefail

setup_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="$setup_dir/toolchain.json"
check_only=0
case "${1:-}" in
    --check) check_only=1 ;;
    --help|-h)
        echo "Usage: bash .devcontainer/scripts/setup-tools.sh [--check]"
        echo "Install pinned user tools, or check the environment without downloading."
        exit 0 ;;
    "") ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then
    echo "Expected at most one option." >&2
    exit 2
fi

fail() { echo "$*" >&2; exit 1; }
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    fail "The build environment must be Linux x86_64."
fi
for command_name in curl jq sha256sum unzip python3 x86_64-w64-mingw32-gcc xvfb-run xauth; do
    command -v "$command_name" >/dev/null || fail "$command_name is missing. Rebuild the devcontainer."
done
wine_path=""
for candidate in "$(command -v wine64 || true)" /usr/lib/wine/wine64 "$(command -v wine || true)"; do
    if [[ -f "$candidate" ]]; then
        wine_path="$(readlink -f -- "$candidate")"
        break
    fi
done
[[ -n "$wine_path" ]] || fail "Wine is missing. Rebuild the devcontainer."
server_path=""
for candidate in "$(command -v wineserver || true)" "${wine_path%/*}/wineserver" \
    "${wine_path%/*}/wineserver64" /usr/lib/x86_64-linux-gnu/wine/wineserver /usr/lib/wine/wineserver64; do
    if [[ -f "$candidate" ]]; then
        server_path="$candidate"
        break
    fi
done
[[ -n "$server_path" ]] || fail "Cannot locate Wine's matching wineserver."

value() { jq -er "$1 | select(type == \"string\" and length > 0)" "$lock_file"; }
tools_root="${KEYBIND_TOOLS_DIR:-$HOME/.local/share/keybind-tools}"
# Match the build's explicit tool paths without changing a developer's default.
export CARGO_HOME="$HOME/.cargo" RUSTUP_HOME="$HOME/.rustup"
rustup_bin="$CARGO_HOME/bin/rustup"
cargo_bin="$CARGO_HOME/bin/cargo"
rust_version="$(value '.rust.version')"
rust_target="$(value '.rust.target')"
ahk_version="$(value '.autohotkey.version')"
compiler_version="$(value '.ahk2exe.version')"
ahk_dir="$tools_root/autohotkey-$ahk_version"
compiler_dir="$tools_root/ahk2exe-$compiler_version"
partial_file=""
trap 'if [[ -n "$partial_file" ]]; then rm -f -- "$partial_file"; fi' EXIT

verify_hash() {
    [[ "$(sha256sum -- "$1" | cut -d ' ' -f 1)" == "$2" ]]
}
fetch() {
    local item="$1" destination="$2" url expected_hash
    url="$(value ".$item.url")"
    expected_hash="$(value ".$item.sha256")"
    if [[ -f "$destination" ]] && verify_hash "$destination" "$expected_hash"; then
        return
    fi
    mkdir -p -- "$(dirname -- "$destination")"
    partial_file="$(mktemp "$destination.partial.XXXXXX")"
    echo "Downloading $url"
    curl --fail --location --retry 3 --connect-timeout 30 --max-time 300 \
        --user-agent keybind-build --output "$partial_file" "$url"
    verify_hash "$partial_file" "$expected_hash" || fail "SHA256 mismatch: $destination"
    mv -- "$partial_file" "$destination"
    partial_file=""
}

if [[ "$check_only" == 0 ]]; then
    for item in autohotkey ahk2exe; do
        version="$(value ".$item.version")"
        archive="$tools_root/downloads/$item-$version.zip"
        fetch "$item" "$archive"
        destination="$tools_root/$item-$version"
        mkdir -p -- "$destination"
        # Always re-extract verified inputs rather than trusting edited binaries.
        unzip -oq "$archive" -d "$destination"
    done
    if [[ ! -f "$rustup_bin" ]]; then
        installer="$tools_root/downloads/rustup-init"
        fetch rustup "$installer"
        chmod +x "$installer"
        "$installer" -y --profile minimal --no-modify-path --default-toolchain none
    fi
    "$rustup_bin" set auto-self-update disable
    "$rustup_bin" toolchain install "$rust_version" --profile minimal --target "$rust_target"
    if ! "$rustup_bin" show active-toolchain >/dev/null 2>&1; then
        "$rustup_bin" default "$rust_version"
    fi
fi

for tool_path in "$ahk_dir/AutoHotkey64.exe" "$compiler_dir/Ahk2Exe.exe" "$cargo_bin" "$rustup_bin"; do
    [[ -f "$tool_path" ]] || fail "Missing $tool_path; run bash .devcontainer/scripts/setup-tools.sh"
done
"$cargo_bin" "+$rust_version" --version
installed_targets="$("$rustup_bin" target list --installed --toolchain "$rust_version")"
found_target=0
while IFS= read -r installed_target; do
    if [[ "$installed_target" == "$rust_target" ]]; then
        found_target=1
        break
    fi
done <<< "$installed_targets"
[[ "$found_target" == 1 ]] || fail "The pinned Windows Rust target is not installed."
echo "Pinned Linux/Windows build tools are ready."
