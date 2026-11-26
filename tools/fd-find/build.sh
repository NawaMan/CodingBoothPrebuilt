#!/usr/bin/env bash
# fd from crates.io (crate fd-find) via `cargo install --locked`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_cargo_build fd-find
FD="$CB_CARGO_ROOT/bin/fd"
"$FD" --version | grep -qF "fd $VERSION" \
    || { echo "error: fd --version says '$("$FD" --version)', not $VERSION" >&2; exit 1; }
mkdir -p "$WORK/smoke/sub"
touch "$WORK/smoke/sub/booth.txt" "$WORK/smoke/booth.md" "$WORK/smoke/other.txt"
found=$(cd "$WORK/smoke" && "$FD" -e txt booth)
[[ "$found" == "sub/booth.txt" ]] || { echo "error: fd found '$found'" >&2; exit 1; }
echo "   fd found the one .txt named booth"

cb_cargo_package fd
