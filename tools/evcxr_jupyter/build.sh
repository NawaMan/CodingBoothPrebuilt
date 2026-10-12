#!/usr/bin/env bash
# evcxr_jupyter from crates.io via `cargo install --locked`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt build-essential pkg-config

echo "==> Installing a Rust toolchain (stable, minimal)"
export RUSTUP_HOME="$WORK/rustup" CARGO_HOME="$WORK/cargo"
cb_fetch https://sh.rustup.rs "$WORK/rustup-init.sh"
sh "$WORK/rustup-init.sh" -y -q --profile minimal --no-modify-path >/dev/null
export PATH="$CARGO_HOME/bin:$PATH"
rustc --version

echo "==> cargo install evcxr_jupyter $VERSION"
cargo install --locked --quiet evcxr_jupyter --version "=$VERSION" --root "$WORK/root"

echo "==> Testing"
BIN="$WORK/root/bin/evcxr_jupyter"
libs_missing="$(ldd "$BIN" | grep 'not found' || true)"
[[ -z "$libs_missing" ]] || { echo "error: missing shared libraries: $libs_missing" >&2; exit 1; }
"$BIN" --help >/dev/null 2>&1 || { "$BIN" --help; echo "error: evcxr_jupyter --help failed" >&2; exit 1; }
echo "smoke tests passed"

mkdir -p "$PKG_DIR/bin"
cp "$BIN" "$PKG_DIR/bin/"
strip "$PKG_DIR/bin/evcxr_jupyter"
SRC_CRATE="$(find "$CARGO_HOME/registry/src" -maxdepth 2 -type d -name "evcxr_jupyter-$VERSION" | head -1)"
for f in LICENSE LICENSE-MIT LICENSE-APACHE COPYRIGHT; do
    if [[ -f "$SRC_CRATE/$f" ]]; then cp "$SRC_CRATE/$f" "$PKG_DIR/"; fi
done
{
    echo "source:       crates.io evcxr_jupyter $VERSION (cargo install --locked)"
    echo "compiler:     $(rustc --version)"
} >> "$BUILD_NOTES"
