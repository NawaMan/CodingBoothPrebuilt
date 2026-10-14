#!/usr/bin/env bash
# Newest IHaskell on Hackage, paired with the GHC that ghcup tags "recommended" -- the GHC
# CodingBooth's haskell setup installs by default. Prints e.g. 0.13.0.0-ghc9.10.3.
set -euo pipefail

ihaskell=$(curl -fsSL --retry 3 -H 'Accept: application/json' \
    https://hackage.haskell.org/package/ihaskell/preferred | jq -er '."normal-version"[0]')

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

echo "$ihaskell-ghc$ghc"
