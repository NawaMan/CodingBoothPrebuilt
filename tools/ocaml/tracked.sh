#!/usr/bin/env bash
# The newest patch release of each OCaml series from TRACK_FROM on, plus TRACK_ALSO
# (tool.conf), each with the current tool pins. Prints e.g. 5.5.1-tools1.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

compilers=$(cb_github_releases ocaml/ocaml | cb_newest_per_series "$TRACK_FROM" $TRACK_ALSO)
[[ -n "$compilers" ]] || { echo "error: no stable OCaml releases found" >&2; exit 1; }
sed "s/\$/-tools$TOOLS_REVISION/" <<< "$compilers"
