#!/usr/bin/env bash
# Not upstream's newest release: that one (0.19.2 on) ships official linux binaries for
# both CPUs. The version worth building here is the last one without them (tracked.sh).
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/tracked.sh" | tail -1
