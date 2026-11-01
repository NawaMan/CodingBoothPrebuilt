#!/usr/bin/env bash
# Newest upstream GitHub release.
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_github_latest_release HeidiSQL/HeidiSQL
