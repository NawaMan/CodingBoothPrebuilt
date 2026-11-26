#!/usr/bin/env bash
# Newest protoc-gen-go-grpc module release, from the Go module proxy.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_go_module_latest google.golang.org/grpc/cmd/protoc-gen-go-grpc
