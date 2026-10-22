#!/usr/bin/env bash
# The ormolu versions Stack users get -- those in Stackage LTS from STACKAGE_FROM_LTS on
# (tool.conf), and nightly -- plus upstream's latest release (latest.sh).
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

stackage=$(cb_stackage_versions ormolu "$STACKAGE_FROM_LTS")
latest=$(cb_github_latest_release tweag/ormolu)
{ cut -d' ' -f1 <<< "$stackage"; echo "$latest"; } | grep . | sort -uV
