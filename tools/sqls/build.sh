#!/usr/bin/env bash
# sqls from its release tag, built as upstream's .goreleaser.yml builds the linux binary:
# cgo on (the SQLite driver is C), -s -w, and the commit in main.revision.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt build-essential git python3 sqlite3

# The newest Go from go.dev; go.mod's toolchain line fetches another if the tag needs one.
case "$ARCH" in x86_64) go_arch=amd64 ;; arm64) go_arch=arm64 ;; esac
go_version=$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | jq -er '.[0].version')
echo "==> Installing $go_version"
cb_fetch "https://go.dev/dl/$go_version.linux-$go_arch.tar.gz" "$WORK/go.tar.gz"
tar -xzf "$WORK/go.tar.gz" -C "$WORK"
export PATH="$WORK/go/bin:$PATH" GOPATH="$WORK/gopath" GOCACHE="$WORK/gocache" CGO_ENABLED=1

SRC="$WORK/sqls"
echo "==> Cloning sqls-server/sqls v$VERSION"
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$VERSION" https://github.com/sqls-server/sqls "$SRC"
revision=$(git -C "$SRC" rev-parse --short HEAD)

echo "==> Building"
(cd "$SRC" && go build -ldflags "-s -w -X main.revision=$revision" -o "$WORK/sqls-bin" .) \
    > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }

echo "==> Testing"
libs_missing="$(ldd "$WORK/sqls-bin" | grep 'not found' || true)"
[[ -z "$libs_missing" ]] || { echo "error: missing shared libraries: $libs_missing" >&2; exit 1; }
got=$("$WORK/sqls-bin" --version)
[[ "$got" == *"Version:$VERSION,"* ]] || { echo "error: sqls --version printed '$got'" >&2; exit 1; }
echo "$got" | head -1
# A language-server session over stdio against a SQLite database, which goes through the
# cgo driver: completing "SELECT * FROM " has to offer the table.
sqlite3 "$WORK/test.db" 'CREATE TABLE booth_users (id INTEGER PRIMARY KEY, name TEXT);'
python3 - "$WORK/sqls-bin" "$WORK/test.db" <<'PY'
import json, subprocess, sys

exe, db = sys.argv[1], sys.argv[2]
proc = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def send(msg):
    body = json.dumps(msg).encode()
    proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    proc.stdin.flush()

def receive(want_id):
    while True:
        length = 0
        while (line := proc.stdout.readline().strip()):
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":")[1])
        msg = json.loads(proc.stdout.read(length))
        if msg.get("id") == want_id:
            return msg

uri, text = "file:///tmp/t.sql", "SELECT * FROM "
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "processId": None, "rootUri": None, "capabilities": {},
    "initializationOptions": {"connectionConfig": {"driver": "sqlite3", "dataSourceName": db}}}})
assert "capabilities" in receive(1)["result"], "no capabilities in the initialize reply"
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
    "uri": uri, "languageId": "sql", "version": 1, "text": text}}})
send({"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": uri}, "position": {"line": 0, "character": len(text)}}})
result = receive(2)["result"]
items = result["items"] if isinstance(result, dict) else (result or [])
labels = [i["label"] for i in items]
assert "booth_users" in labels, f"completion did not offer the table: {labels}"
print(f"   completion after {text!r} offers booth_users")
send({"jsonrpc": "2.0", "id": 3, "method": "shutdown"})
receive(3)
# sqls does not exit on "exit"; it keeps serving until stopped.
proc.stdin.close()
proc.terminate()
proc.wait(timeout=10)
PY
echo "smoke tests passed"

cp "$WORK/sqls-bin" "$PKG_DIR/sqls"
cp "$SRC/LICENSE" "$PKG_DIR/LICENSE"
{
    echo "source:       https://github.com/sqls-server/sqls at v$VERSION ($revision)"
    echo "compiler:     $(go version | awk '{print $3}'), cgo with $(gcc --version | head -1)"
} >> "$BUILD_NOTES"
