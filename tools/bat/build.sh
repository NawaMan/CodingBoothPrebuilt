#!/usr/bin/env bash
# bat from crates.io via `cargo install --locked`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_cargo_build bat
BAT="$CB_CARGO_ROOT/bin/bat"
export HOME="$WORK"
"$BAT" --version | grep -qF "bat $VERSION" \
    || { echo "error: bat --version says '$("$BAT" --version)', not $VERSION" >&2; exit 1; }
printf 'fn main() {\n    println!("booth");\n}\n' > "$WORK/smoke.rs"
shown=$("$BAT" --plain --paging=never --color=always "$WORK/smoke.rs")
grep -q $'\e\[' <<< "$shown" && grep -qF 'booth' <<< "$shown" \
    || { echo "error: bat did not highlight the sample: $shown" >&2; exit 1; }
echo "   bat highlighted a Rust file"

cb_cargo_package bat
