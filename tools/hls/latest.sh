#!/usr/bin/env bash
# The newest tracked HLS paired with the newest tracked GHC it supports: the last line of
# tracked.sh. Prints e.g. 2.15.0.0-ghc9.14.1.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/tracked.sh" | tail -1
