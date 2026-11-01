#!/usr/bin/env bash
# GoNB at its release tag via `go install`, the way its README installs it. Called by
# ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git python3 python3-jupyter-client

# The newest Go from go.dev; go.mod's toolchain line fetches another if the tag needs one.
case "$ARCH" in x86_64) go_arch=amd64 ;; arm64) go_arch=arm64 ;; esac
go_version=$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | jq -er '.[0].version')
echo "==> Installing $go_version"
cb_fetch "https://go.dev/dl/$go_version.linux-$go_arch.tar.gz" "$WORK/go.tar.gz"
tar -xzf "$WORK/go.tar.gz" -C "$WORK"
export PATH="$WORK/go/bin:$WORK/gopath/bin:$PATH" GOPATH="$WORK/gopath" GOCACHE="$WORK/gocache" CGO_ENABLED=0

echo "==> go install github.com/janpfeifer/gonb@v$VERSION"
GOBIN="$WORK/bin" go install "github.com/janpfeifer/gonb@v$VERSION" > "$WORK/build.log" 2>&1 \
    || { tail -80 "$WORK/build.log"; exit 1; }

echo "==> Testing"
BIN="$WORK/bin/gonb"
built=$(go version -m "$BIN" | awk '$1 == "mod" { print $3 }')
[[ "$built" == "v$VERSION" ]] || { echo "error: $BIN reports module version '$built', not v$VERSION" >&2; exit 1; }
# A real kernel session: start it through jupyter_client and run a cell, which GoNB compiles
# with the go toolchain after running goimports on it.
go install golang.org/x/tools/cmd/goimports@latest > "$WORK/goimports.log" 2>&1 \
    || { tail -40 "$WORK/goimports.log"; exit 1; }
mkdir -p "$WORK/kernels/gonb"
cat > "$WORK/kernels/gonb/kernel.json" <<KJSON
{"argv": ["$BIN", "--kernel", "{connection_file}"], "display_name": "Go (GoNB)", "language": "go"}
KJSON
JUPYTER_PATH="$WORK" HOME="$WORK" python3 - <<'PY'
import jupyter_client

km, kc = jupyter_client.manager.start_new_kernel(kernel_name="gonb")
try:
    out = []
    def collect(msg):
        if msg["msg_type"] == "stream":
            out.append(msg["content"]["text"])
        elif msg["msg_type"] == "error":
            out.append("ERROR: " + msg["content"]["evalue"])
    reply = kc.execute_interactive('%%\nfmt.Printf("booth %d\\n", 6*7)', timeout=300, output_hook=collect)
    text = "".join(out)
    assert reply["content"]["status"] == "ok" and "booth 42" in text, f"cell gave {reply['content']['status']}: {text!r}"
    print("   kernel ran a cell: " + text.strip())
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)
PY
echo "smoke tests passed"

mkdir -p "$PKG_DIR/bin"
cp "$BIN" "$PKG_DIR/bin/"
SRC_MOD="$GOPATH/pkg/mod/github.com/janpfeifer/gonb@v$VERSION"
cp "$SRC_MOD/LICENSE" "$PKG_DIR/LICENSE"
{
    echo "source:       github.com/janpfeifer/gonb@v$VERSION (go install, CGO_ENABLED=0)"
    echo "compiler:     $(go version -m "$BIN" | head -1 | awk '{print $2}')"
} >> "$BUILD_NOTES"
