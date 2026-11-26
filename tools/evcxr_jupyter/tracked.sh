#!/usr/bin/env bash
# TRACK_ALSO (tool.conf) and the newest evcxr_jupyter on crates.io.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
source "$here/tool.conf"

{ printf '%s\n' $TRACK_ALSO; bash "$here/latest.sh"; } | sort -uV
