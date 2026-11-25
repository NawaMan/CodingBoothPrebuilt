#!/usr/bin/env bash
# goimports at a golang.org/x/tools release via `go install`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git
cb_install_go

MODULE=golang.org/x/tools
echo "==> go install $MODULE/cmd/goimports@v$VERSION"
GOBIN="$WORK/bin" go install "$MODULE/cmd/goimports@v$VERSION" > "$WORK/build.log" 2>&1 \
    || { tail -80 "$WORK/build.log"; exit 1; }

echo "==> Testing"
BIN="$WORK/bin/goimports"
built=$(go version -m "$BIN" | awk '$1 == "mod" { print $3 }')
[[ "$built" == "v$VERSION" ]] || { echo "error: $BIN reports module version '$built', not v$VERSION" >&2; exit 1; }
file "$BIN" | grep -q "statically linked" || { echo "error: $BIN is not static: $(file "$BIN")" >&2; exit 1; }
# It must add a missing standard-library import and format the file.
printf 'package main\nfunc main() {   fmt.Println("booth")\n}\n' > "$WORK/smoke.go"
fixed=$("$BIN" "$WORK/smoke.go")
grep -q '^import "fmt"$' <<< "$fixed" && grep -qF '	fmt.Println("booth")' <<< "$fixed" \
    || { echo "error: goimports did not fix the sample:" >&2; echo "$fixed" >&2; exit 1; }
echo "   goimports added the fmt import"
echo "smoke tests passed"

mkdir -p "$PKG_DIR/bin"
cp "$BIN" "$PKG_DIR/bin/"
cp "$(go env GOMODCACHE)/$MODULE@v$VERSION/LICENSE" "$PKG_DIR/LICENSE"
{
    echo "source:       $MODULE/cmd/goimports@v$VERSION (go install, CGO_ENABLED=0)"
    echo "compiler:     $(go version -m "$BIN" | head -1 | awk '{print $2}')"
} >> "$BUILD_NOTES"
