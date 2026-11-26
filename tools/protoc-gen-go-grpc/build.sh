#!/usr/bin/env bash
# protoc-gen-go-grpc at its module release via `go install`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git protobuf-compiler
cb_install_go
MODULE=google.golang.org/grpc/cmd/protoc-gen-go-grpc
cb_go_build "$MODULE" "$MODULE"

# protoc drives the plugin: a service has to come out as a Go server interface.
mkdir -p "$WORK/proto" "$WORK/out"
cat > "$WORK/proto/booth.proto" <<'PROTO'
syntax = "proto3";
package booth;
option go_package = "example.com/booth;booth";
message Greeting { string name = 1; }
service Greeter { rpc Greet(Greeting) returns (Greeting); }
PROTO
protoc --plugin=protoc-gen-go-grpc="$CB_GO_BIN" -I "$WORK/proto" \
    --go-grpc_out="$WORK/out" --go-grpc_opt=paths=source_relative booth.proto
grep -q '^type GreeterServer interface' "$WORK/out/booth_grpc.pb.go" \
    || { ls -R "$WORK/out"; echo "error: protoc --go-grpc_out did not generate GreeterServer" >&2; exit 1; }
echo "   protoc --go-grpc_out generates booth_grpc.pb.go with interface GreeterServer"

# The module zip holds only the command's folder, not grpc-go's root LICENSE.
cb_go_package https://raw.githubusercontent.com/grpc/grpc-go/master/LICENSE
