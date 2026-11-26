#!/usr/bin/env bash
# Newest golangci-lint, from the Go module proxy's v2 module.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest github.com/golangci/golangci-lint/v2
