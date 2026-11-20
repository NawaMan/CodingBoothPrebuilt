#!/usr/bin/env bash
# The newest release tarball of each Bash series from TRACK_FROM on (tool.conf). A series'
# first release has no patch number (5.3), so cb_newest_per_series, which wants X.Y.Z, does
# not fit.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

versions=$(curl -fsSL --retry 3 https://ftp.gnu.org/gnu/bash/ \
    | grep -oE 'bash-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz"' | sed -E 's/^bash-(.*)\.tar\.gz"$/\1/' \
    | sort -uV)
[[ -n "$versions" ]] || { echo "error: no Bash release tarballs found" >&2; exit 1; }

awk -F. -v from="$TRACK_FROM" '
    BEGIN { split(from, f, ".") }
    $1 > f[1] || ($1 == f[1] && $2 >= f[2]) { newest[$1 "." $2] = $0 }
    END { for (s in newest) print newest[s] }' <<< "$versions" | sort -V
