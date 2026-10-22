#!/usr/bin/env bash
# The newest patch release of each GHC series from TRACK_FROM on (tool.conf), from
# ghcup's metadata: the versions Stackage LTS snapshots and most projects pin.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

# Same metadata walk as latest.sh, printing every GHC version key.
metadata=$(curl -fsSL --retry 3 https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml)
versions=$(awk '
        /^ghcupDownloads:/      { downloads = 1; next }
        !downloads              { next }
        /^  [A-Za-z]/           { section = $1 }
        section != "GHC:"       { next }
        /^      [0-9][0-9.]*:$/ { version = $1; sub(/:$/, "", version); print version }' <<< "$metadata")
[[ -n "$versions" ]] || { echo "error: no GHC versions in ghcup metadata" >&2; exit 1; }

cb_newest_per_series "$TRACK_FROM" <<< "$versions"
