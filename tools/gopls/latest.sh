#!/usr/bin/env bash
# Newest gopls release, from the Go module proxy (gopls is its own module, tagged gopls/vX.Y.Z).
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest golang.org/x/tools/gopls
