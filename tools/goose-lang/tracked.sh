#!/usr/bin/env bash
# The newest TRACK_LATEST (tool.conf) Goose releases, oldest first.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

releases=$(cb_github_releases aardappel/goose | grep -E '^[0-9]{4}\.[0-9]+(\.[0-9]+)?$' || true)
[[ -n "$releases" ]] || { echo "error: no Goose releases found" >&2; exit 1; }
sort -V <<< "$releases" | tail -n "$TRACK_LATEST"
