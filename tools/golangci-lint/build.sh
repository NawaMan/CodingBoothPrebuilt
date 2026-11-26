#!/usr/bin/env bash
# golangci-lint at a release via `go install`, from the Go module of its major version.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git
cb_install_go
# Each major is its own module (.../v2); 1.x cannot load packages built by current Go.
[[ "$VERSION" != 1.* ]] || { echo "error: golangci-lint 1.x fails on current Go; build 2.x or later" >&2; exit 1; }
MODULE="github.com/golangci/golangci-lint/v${VERSION%%.*}"
cb_go_build "$MODULE" "$MODULE/cmd/golangci-lint"

# It must pass a clean module and flag an unchecked error in another.
export HOME="$WORK" XDG_CACHE_HOME="$WORK/cache" GOLANGCI_LINT_CACHE="$WORK/lint-cache"
for case in clean dirty; do
    mkdir -p "$WORK/$case"
    printf 'module example.com/%s\n\ngo 1.21\n' "$case" > "$WORK/$case/go.mod"
done
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("booth") }\n' > "$WORK/clean/main.go"
printf 'package main\n\nimport "os"\n\nfunc main() { os.Remove("booth") }\n' > "$WORK/dirty/main.go"
(cd "$WORK/clean" && "$CB_GO_BIN" run ./... > "$WORK/clean.log" 2>&1) \
    || { cat "$WORK/clean.log"; echo "error: golangci-lint failed a clean module" >&2; exit 1; }
if (cd "$WORK/dirty" && "$CB_GO_BIN" run ./... > "$WORK/dirty.log" 2>&1); then
    cat "$WORK/dirty.log"; echo "error: golangci-lint passed an unchecked os.Remove" >&2; exit 1
fi
grep -q errcheck "$WORK/dirty.log" \
    || { cat "$WORK/dirty.log"; echo "error: golangci-lint did not report errcheck" >&2; exit 1; }
echo "   golangci-lint passes a clean module and reports errcheck on an unchecked error"

cb_go_package https://raw.githubusercontent.com/golangci/golangci-lint/main/LICENSE
