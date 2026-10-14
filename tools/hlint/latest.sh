#!/usr/bin/env bash
# Newest upstream GitHub release, so the arm64 build matches upstream's x86_64 binary.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_github_latest_release ndmitchell/hlint
