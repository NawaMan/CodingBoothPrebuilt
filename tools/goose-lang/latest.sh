#!/usr/bin/env bash
# Newest upstream GitHub release, so the arm64 build matches upstream's x64 one.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_github_latest_release aardappel/goose
