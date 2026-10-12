#!/usr/bin/env bash
# Newest scratch-gui GitHub release (the repo is archived, so this stays at 5.3.0).
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_github_latest_release scratchfoundation/scratch-gui
