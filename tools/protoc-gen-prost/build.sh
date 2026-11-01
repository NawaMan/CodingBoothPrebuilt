#!/usr/bin/env bash
# protoc-gen-prost from crates.io via `cargo install --locked`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt build-essential pkg-config protobuf-compiler

echo "==> Installing a Rust toolchain (stable, minimal)"
export RUSTUP_HOME="$WORK/rustup" CARGO_HOME="$WORK/cargo"
cb_fetch https://sh.rustup.rs "$WORK/rustup-init.sh"
sh "$WORK/rustup-init.sh" -y -q --profile minimal --no-modify-path >/dev/null
export PATH="$CARGO_HOME/bin:$PATH"
rustc --version

echo "==> cargo install protoc-gen-prost $VERSION"
cargo install --locked --quiet protoc-gen-prost --version "=$VERSION" --root "$WORK/root"

echo "==> Testing"
BIN="$WORK/root/bin/protoc-gen-prost"
libs_missing="$(ldd "$BIN" | grep 'not found' || true)"
[[ -z "$libs_missing" ]] || { echo "error: missing shared libraries: $libs_missing" >&2; exit 1; }
# protoc drives the plugin: a message has to come out as a Prost! struct.
mkdir -p "$WORK/proto" "$WORK/out"
cat > "$WORK/proto/booth.proto" <<'PROTO'
syntax = "proto3";
package booth;
message Greeting { string name = 1; int32 times = 2; }
PROTO
protoc --plugin=protoc-gen-prost="$BIN" -I "$WORK/proto" --prost_out="$WORK/out" booth.proto
# Output goes into a folder per package: out/booth/booth.rs.
grep -q 'pub struct Greeting' "$WORK/out/booth/booth.rs" \
    || { ls -R "$WORK/out"; echo "error: protoc --prost_out did not generate struct Greeting" >&2; exit 1; }
echo "   protoc --prost_out generates booth/booth.rs with struct Greeting"
echo "smoke tests passed"

mkdir -p "$PKG_DIR/bin"
cp "$BIN" "$PKG_DIR/bin/"
strip "$PKG_DIR/bin/protoc-gen-prost"
SRC_CRATE="$(find "$CARGO_HOME/registry/src" -maxdepth 2 -type d -name "protoc-gen-prost-$VERSION" | head -1)"
for f in LICENSE LICENSE-MIT LICENSE-APACHE COPYRIGHT; do
    if [[ -f "$SRC_CRATE/$f" ]]; then cp "$SRC_CRATE/$f" "$PKG_DIR/"; fi
done
{
    echo "source:       crates.io protoc-gen-prost $VERSION (cargo install --locked)"
    echo "compiler:     $(rustc --version)"
} >> "$BUILD_NOTES"
