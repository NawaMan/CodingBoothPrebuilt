#!/usr/bin/env bash
# Newest make-X.Y[.Z].tar.gz in the GNU make directory listing.
set -euo pipefail
source "$ROOT/lib/common.sh"

listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
cb_fetch_gnu make/ "$listing"
grep -oE 'make-[0-9]+(\.[0-9]+)+\.tar\.gz' "$listing" \
    | sed -E 's/^make-(.*)\.tar\.gz$/\1/' | sort -uV | tail -1
