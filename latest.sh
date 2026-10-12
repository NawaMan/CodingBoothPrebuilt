#!/usr/bin/env bash
#
# Print the newest upstream version of a tool.
#
# Usage: ./latest.sh <tool>
#
# Runs on the host (the workflow's plan job); needs curl and jq.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

TOOL="${1:?usage: $0 <tool>}"
TOOL_DIR="$ROOT/tools/$TOOL"
[[ -f "$TOOL_DIR/latest.sh" ]] || { echo "error: unknown tool '$TOOL' (no $TOOL_DIR/latest.sh)" >&2; exit 1; }

export ROOT
version="$(bash "$TOOL_DIR/latest.sh")"
[[ "$version" =~ ^[0-9][0-9A-Za-z.+_-]*$ ]] \
    || { echo "error: $TOOL_DIR/latest.sh printed '$version', not a version" >&2; exit 1; }
echo "$version"
