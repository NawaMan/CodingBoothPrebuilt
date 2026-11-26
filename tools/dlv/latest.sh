#!/usr/bin/env bash
# Newest Delve release, from the Go module proxy (the version `go install ...@latest` gets).
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest github.com/go-delve/delve
