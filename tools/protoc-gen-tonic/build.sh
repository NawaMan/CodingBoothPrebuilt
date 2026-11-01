#!/usr/bin/env bash
# protoc-gen-tonic from crates.io via `cargo install --locked`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt build-essential pkg-config protobuf-compiler

echo "==> Installing a Rust toolchain (stable, minimal)"
export RUSTUP_HOME="$WORK/rustup" CARGO_HOME="$WORK/cargo"
cb_fetch https://sh.rustup.rs "$WORK/rustup-init.sh"
sh "$WORK/rustup-init.sh" -y -q --profile minimal --no-modify-path >/dev/null
export PATH="$CARGO_HOME/bin:$PATH"
rustc --version

echo "==> cargo install protoc-gen-tonic $VERSION"
cargo install --locked --quiet protoc-gen-tonic --version "=$VERSION" --root "$WORK/root"

echo "==> Testing"
BIN="$WORK/root/bin/protoc-gen-tonic"
libs_missing="$(ldd "$BIN" | grep 'not found' || true)"
[[ -z "$libs_missing" ]] || { echo "error: missing shared libraries: $libs_missing" >&2; exit 1; }
# protoc drives the plugin: a service has to come out as a Tonic client and server. Tonic
# inserts its code into the file protoc-gen-prost writes, so that plugin runs alongside
# (built here for the test only, not shipped).
cargo install --locked --quiet protoc-gen-prost --root "$WORK/prost"
mkdir -p "$WORK/proto" "$WORK/out"
cat > "$WORK/proto/booth.proto" <<'PROTO'
syntax = "proto3";
package booth;
message Greeting { string name = 1; }
service Greeter { rpc Greet (Greeting) returns (Greeting); }
PROTO
protoc --plugin=protoc-gen-prost="$WORK/prost/bin/protoc-gen-prost" --plugin=protoc-gen-tonic="$BIN" \
    -I "$WORK/proto" --prost_out="$WORK/out" --tonic_out="$WORK/out" booth.proto
# Tonic writes booth/booth.tonic.rs and includes it from the end of prost's booth/booth.rs.
grep -qs 'booth.tonic.rs' "$WORK/out/booth/booth.rs" \
    && grep -qs 'GreeterClient' "$WORK/out/booth/booth.tonic.rs" && grep -qs 'GreeterServer' "$WORK/out/booth/booth.tonic.rs" \
    || { ls -R "$WORK/out"; echo "error: protoc --tonic_out did not generate GreeterClient and GreeterServer" >&2; exit 1; }
echo "   protoc --tonic_out writes booth/booth.tonic.rs with GreeterClient and GreeterServer"
echo "smoke tests passed"

mkdir -p "$PKG_DIR/bin"
cp "$BIN" "$PKG_DIR/bin/"
strip "$PKG_DIR/bin/protoc-gen-tonic"
SRC_CRATE="$(find "$CARGO_HOME/registry/src" -maxdepth 2 -type d -name "protoc-gen-tonic-$VERSION" | head -1)"
for f in LICENSE LICENSE-MIT LICENSE-APACHE COPYRIGHT; do
    if [[ -f "$SRC_CRATE/$f" ]]; then cp "$SRC_CRATE/$f" "$PKG_DIR/"; fi
done
{
    echo "source:       crates.io protoc-gen-tonic $VERSION (cargo install --locked)"
    echo "tested with:  $(cargo install --list --root "$WORK/prost" | head -1 | tr -d :)"
    echo "compiler:     $(rustc --version)"
} >> "$BUILD_NOTES"
