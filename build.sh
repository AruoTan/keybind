#!/usr/bin/env bash
set -euo pipefail
task_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    exec python3 "$task_script_dir/scripts/build.py" "$@"
fi
if [[ "${KEYBIND_HEADLESS_BUILD:-}" != 1 ]]; then
    exec xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
        env KEYBIND_HEADLESS_BUILD=1 python3 "$task_script_dir/scripts/build.py" "$@"
fi
exec python3 "$task_script_dir/scripts/build.py" "$@"
