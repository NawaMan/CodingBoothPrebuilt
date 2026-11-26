#!/usr/bin/env bash
# hey at its release tag via `go install`. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt git python3
cb_install_go
cb_go_build github.com/rakyll/hey github.com/rakyll/hey

# Load a real local server and count the responses.
mkdir -p "$WORK/www" && echo booth > "$WORK/www/index.html"
port=$(( 20000 + RANDOM % 20000 ))
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$WORK/www" > "$WORK/http.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$port/" > /dev/null && break; sleep 0.2; done
report=$("$CB_GO_BIN" -n 4 -c 2 "http://127.0.0.1:$port/")
grep -qE '\[200\][[:space:]]+4 responses' <<< "$report" \
    || { echo "$report"; echo "error: hey did not get 4 x 200 from a local server" >&2; exit 1; }
echo "   hey sent 4 requests and got [200] 4 responses"

cb_go_package
