#!/usr/bin/env bash
# The hlint versions Stack users get -- those in Stackage LTS from STACKAGE_FROM_LTS on
# (tool.conf), and nightly -- plus upstream's latest release (latest.sh).
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

stackage=$(cb_stackage_versions hlint "$STACKAGE_FROM_LTS")
latest=$(cb_github_latest_release ndmitchell/hlint)
{ cut -d' ' -f1 <<< "$stackage"; echo "$latest"; } | grep . | sort -uV
