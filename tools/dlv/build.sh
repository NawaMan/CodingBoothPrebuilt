#!/usr/bin/env bash
# Delve at its release tag via `go install`, the way its docs install it. Called by
# ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git
cb_install_go
cb_go_build github.com/go-delve/delve github.com/go-delve/delve/cmd/dlv

reported=$("$CB_GO_BIN" version 2>&1)
grep -qF "Version: $VERSION" <<< "$reported" || { echo "error: 'dlv version' says '$reported', not $VERSION" >&2; exit 1; }
echo "   dlv $(grep -m1 Version: <<< "$reported")"
# A real debug session: stop at a breakpoint and evaluate an expression in the stopped program.
mkdir -p "$WORK/smoke"
printf 'module example.com/smoke\n\ngo 1.21\n' > "$WORK/smoke/go.mod"
printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tanswer := 6 * 7\n\tfmt.Println(answer)\n}\n' > "$WORK/smoke/main.go"
session=$(cd "$WORK/smoke" && printf 'break main.go:7\ncontinue\nprint answer\nexit\n' \
    | HOME="$WORK" timeout 300 "$CB_GO_BIN" debug --allow-non-terminal-interactive=true 2>&1) || true
grep -qE '^(\(dlv\) )?42$' <<< "$session" \
    || { echo "error: dlv did not stop and print answer=42:" >&2; echo "$session" >&2; exit 1; }
echo "   dlv stopped at a breakpoint and printed answer = 42"

cb_go_package
