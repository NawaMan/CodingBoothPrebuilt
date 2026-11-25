#!/usr/bin/env bash
# The wails3 CLI at its release tag via `go install`, the way upstream's docs install it.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git
cb_install_go

MODULE=github.com/wailsapp/wails/v3
echo "==> go install $MODULE/cmd/wails3@v$VERSION"
GOBIN="$WORK/bin" go install "$MODULE/cmd/wails3@v$VERSION" > "$WORK/build.log" 2>&1 \
    || { tail -80 "$WORK/build.log"; exit 1; }

echo "==> Testing"
BIN="$WORK/bin/wails3"
built=$(go version -m "$BIN" | awk '$1 == "mod" { print $3 }')
[[ "$built" == "v$VERSION" ]] || { echo "error: $BIN reports module version '$built', not v$VERSION" >&2; exit 1; }
file "$BIN" | grep -q "statically linked" || { echo "error: $BIN is not static: $(file "$BIN")" >&2; exit 1; }
reported=$("$BIN" version 2>&1)
grep -qF "$VERSION" <<< "$reported" || { echo "error: '$BIN version' says '$reported', not $VERSION" >&2; exit 1; }
echo "   wails3 version: $reported"
# Scaffold a project, which exercises the embedded templates without needing WebKitGTK.
(cd "$WORK" && HOME="$WORK" "$BIN" init -n smoke -t vanilla -q > "$WORK/init.log" 2>&1) \
    || { tail -40 "$WORK/init.log"; exit 1; }
[[ -f "$WORK/smoke/main.go" ]] || { echo "error: wails3 init made no smoke/main.go" >&2; cat "$WORK/init.log"; exit 1; }
echo "   wails3 init scaffolded a project"
echo "smoke tests passed"

mkdir -p "$PKG_DIR/bin"
cp "$BIN" "$PKG_DIR/bin/"
# The v3 module sits in a subfolder, so its zip may not carry the repo-root LICENSE.
mod_license="$(go env GOMODCACHE)/$MODULE@v$VERSION/LICENSE"
if [[ -f "$mod_license" ]]; then cp "$mod_license" "$PKG_DIR/LICENSE"
else cb_fetch "https://raw.githubusercontent.com/wailsapp/wails/v$VERSION/LICENSE" "$PKG_DIR/LICENSE"; fi
{
    echo "source:       $MODULE/cmd/wails3@v$VERSION (go install, CGO_ENABLED=0)"
    echo "compiler:     $(go version -m "$BIN" | head -1 | awk '{print $2}')"
} >> "$BUILD_NOTES"
