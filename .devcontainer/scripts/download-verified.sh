#!/usr/bin/env bash
# Download from ordered sources, promoting only bytes matching the pinned hash.
keybind_download_verified() (
    set -euo pipefail
    local destination="$1" expected_hash="$2" url actual_hash partial_file
    shift 2
    if [[ -f "$destination" ]] && [[ "$(sha256sum -- "$destination" | cut -d ' ' -f 1)" == "$expected_hash" ]]; then
        return 0
    fi
    mkdir -p -- "$(dirname -- "$destination")"
    partial_file="$(mktemp "$destination.partial.XXXXXX")"
    trap 'rm -f -- "$partial_file"' EXIT
    for url in "$@"; do
        echo "Downloading $url"
        : > "$partial_file"
        if curl --fail --location --silent --show-error --retry 3 --connect-timeout 30 --max-time 300 \
            --user-agent keybind-build --output "$partial_file" "$url"; then
            actual_hash="$(sha256sum -- "$partial_file" | cut -d ' ' -f 1)"
            if [[ "$actual_hash" == "$expected_hash" ]]; then
                mv -- "$partial_file" "$destination"
                return 0
            fi
            echo "SHA256 mismatch: $url; expected=$expected_hash; actual=$actual_hash" >&2
        else
            echo "Download failed: $url" >&2
        fi
    done
    echo "No download matched the pinned SHA256: $destination" >&2
    return 1
)
