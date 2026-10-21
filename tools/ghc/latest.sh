#!/usr/bin/env bash
# The GHC that ghcup tags "recommended" -- the one CodingBooth's haskell setup installs by
# default. Other versions (e.g. 9.12.4 for the IHaskell kernel) are built by a manual run
# with explicit versions.
set -euo pipefail

# ghcup's own metadata (ghcup-0.1.0.yaml is the file ghcup 0.2.x reads). Under
# ghcupDownloads → GHC → toolVersions, each version is a 6-space-indented key; the one
# whose viTags lists "Recommended" wins. Read it whole first: awk stops at the first
# match, which would break curl's pipe.
metadata=$(curl -fsSL --retry 3 https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml)
ghc=$(awk '
        /^ghcupDownloads:/      { downloads = 1; next }
        !downloads              { next }
        /^  [A-Za-z]/           { section = $1 }
        section != "GHC:"       { next }
        /^      [0-9][0-9.]*:$/ { version = $1; sub(/:$/, "", version) }
        /^ *- Recommended$/     { print version; exit }' <<< "$metadata")
[[ -n "$ghc" ]] || { echo "error: no recommended GHC in ghcup metadata" >&2; exit 1; }

echo "$ghc"
