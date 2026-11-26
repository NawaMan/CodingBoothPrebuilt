#!/usr/bin/env bash
# Newest google.golang.org/protobuf release, from the Go module proxy.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest google.golang.org/protobuf
