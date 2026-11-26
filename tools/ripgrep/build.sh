#!/usr/bin/env bash
# ripgrep from crates.io via `cargo install --locked`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_cargo_build ripgrep
RG="$CB_CARGO_ROOT/bin/rg"
"$RG" --version | head -1 | grep -qF "ripgrep $VERSION" \
    || { echo "error: rg --version says '$("$RG" --version | head -1)', not $VERSION" >&2; exit 1; }
mkdir -p "$WORK/smoke/sub"
printf 'alpha\ncoding booth\n' > "$WORK/smoke/sub/a.txt"
printf 'nothing here\n' > "$WORK/smoke/b.txt"
found=$("$RG" -n booth "$WORK/smoke")
[[ "$found" == "$WORK/smoke/sub/a.txt:2:coding booth" ]] \
    || { echo "error: rg found '$found'" >&2; exit 1; }
echo "   rg found the one match, with its line number"

cb_cargo_package rg
