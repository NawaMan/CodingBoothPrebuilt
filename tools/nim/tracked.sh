#!/usr/bin/env bash
# The newest patch release of each Nim series from TRACK_FROM on (tool.conf), from the
# nim-lang/Nim release tags, keeping only those nim-lang.org has a source tarball for.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

tags=$(git ls-remote --tags --refs https://github.com/nim-lang/Nim 'v*' | sed -nE 's|.*refs/tags/v||p')
[[ -n "$tags" ]] || { echo "error: no Nim release tags found" >&2; exit 1; }

cb_newest_per_series "$TRACK_FROM" <<< "$tags" | while read -r version; do
    if curl -fsIL --retry 3 -o /dev/null "https://nim-lang.org/download/nim-$version.tar.xz"; then
        echo "$version"
    else
        echo "warning: nim $version is tagged but has no source tarball yet; skipped" >&2
    fi
done
