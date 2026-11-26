#!/usr/bin/env bash
# gopls at its module release via `go install`, the way its docs install it. Called by
# ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git
cb_install_go
cb_go_build golang.org/x/tools/gopls golang.org/x/tools/gopls

reported=$(HOME="$WORK" "$CB_GO_BIN" version 2>&1)
grep -qF "v$VERSION" <<< "$reported" || { echo "error: 'gopls version' says '$reported', not v$VERSION" >&2; exit 1; }
echo "   $(head -1 <<< "$reported")"
# It must load a module through the go toolchain and format a file in it.
mkdir -p "$WORK/smoke"
printf 'module example.com/smoke\n\ngo 1.21\n' > "$WORK/smoke/go.mod"
printf 'package main\nimport "fmt"\nfunc main() {   fmt.Println("booth")\n}\n' > "$WORK/smoke/main.go"
formatted=$(cd "$WORK/smoke" && HOME="$WORK" "$CB_GO_BIN" format main.go)
grep -qF '	fmt.Println("booth")' <<< "$formatted" \
    || { echo "error: gopls format did not format the sample:" >&2; echo "$formatted" >&2; exit 1; }
echo "   gopls format reformatted a module's file"

cb_go_package https://raw.githubusercontent.com/golang/tools/master/LICENSE
