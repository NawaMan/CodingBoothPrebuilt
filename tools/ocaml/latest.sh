#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"
compiler=$(cb_github_latest_release ocaml/ocaml)
[[ "$compiler" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: expected a stable OCaml release, got '$compiler'" >&2; exit 1;
}
echo "$compiler-tools$TOOLS_REVISION"
