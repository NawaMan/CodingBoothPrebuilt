#!/usr/bin/env bash
#
# Print the newest upstream version of a tool, or with --tracked every version worth
# prebuilding, one per line (tools/<tool>/tracked.sh; tools without one track latest).
#
# Usage: ./latest.sh [--tracked] <tool>
#
# Runs on the host (the workflow's plan job); needs curl and jq.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

script=latest.sh
[[ "${1:-}" == --tracked ]] && { script=tracked.sh; shift; }
TOOL="${1:?usage: $0 [--tracked] <tool>}"
TOOL_DIR="$ROOT/tools/$TOOL"
[[ -f "$TOOL_DIR/latest.sh" ]] || { echo "error: unknown tool '$TOOL' (no $TOOL_DIR/latest.sh)" >&2; exit 1; }
[[ -f "$TOOL_DIR/$script" ]] || script=latest.sh

export ROOT
versions="$(bash "$TOOL_DIR/$script")"
[[ -n "$versions" ]] || { echo "error: $TOOL_DIR/$script printed nothing" >&2; exit 1; }
while read -r version; do
    [[ "$version" =~ ^[0-9][0-9A-Za-z.+_-]*$ ]] \
        || { echo "error: $TOOL_DIR/$script printed '$version', not a version" >&2; exit 1; }
done <<< "$versions"
echo "$versions"
