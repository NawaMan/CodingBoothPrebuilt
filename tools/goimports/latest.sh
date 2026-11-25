#!/usr/bin/env bash
# Newest golang.org/x/tools release, from the Go module proxy (the repo has tags, no releases).
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest golang.org/x/tools
