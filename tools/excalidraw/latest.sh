#!/usr/bin/env bash
# Newest Excalidraw GitHub release.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_github_latest_release excalidraw/excalidraw
