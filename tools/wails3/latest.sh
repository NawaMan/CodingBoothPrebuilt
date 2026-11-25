#!/usr/bin/env bash
# Newest v3 release, from the Go module proxy: the repo's GitHub releases mix v2 and v3.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest github.com/wailsapp/wails/v3
