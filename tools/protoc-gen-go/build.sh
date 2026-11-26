#!/usr/bin/env bash
# protoc-gen-go at a google.golang.org/protobuf release via `go install`. Called by
# ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git protobuf-compiler
cb_install_go
cb_go_build google.golang.org/protobuf google.golang.org/protobuf/cmd/protoc-gen-go

# protoc drives the plugin: a message has to come out as a Go struct.
mkdir -p "$WORK/proto" "$WORK/out"
cat > "$WORK/proto/booth.proto" <<'PROTO'
syntax = "proto3";
package booth;
option go_package = "example.com/booth;booth";
message Greeting { string name = 1; int32 times = 2; }
PROTO
protoc --plugin=protoc-gen-go="$CB_GO_BIN" -I "$WORK/proto" \
    --go_out="$WORK/out" --go_opt=paths=source_relative booth.proto
grep -q '^type Greeting struct' "$WORK/out/booth.pb.go" \
    || { ls -R "$WORK/out"; echo "error: protoc --go_out did not generate type Greeting" >&2; exit 1; }
echo "   protoc --go_out generates booth.pb.go with type Greeting"

cb_go_package
