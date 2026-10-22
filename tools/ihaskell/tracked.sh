#!/usr/bin/env bash
# The newest IHaskell on Hackage paired with each tracked GHC (../ghc/tracked.sh) from
# TRACK_FROM_GHC (tool.conf) on that its cabal file allows. Prints e.g. 0.13.0.0-ghc9.12.4,
# one per line, oldest GHC first.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

ihaskell=$(curl -fsSL --retry 3 -H 'Accept: application/json' \
    https://hackage.haskell.org/package/ihaskell/preferred | jq -er '."normal-version"[0]')

# The library's build-depends bound on ghc, e.g. "ghc >=8.4 && <9.13": the kernel embeds
# the GHC API, so a GHC outside it cannot build.
bound=$(curl -fsSL --retry 3 "https://hackage.haskell.org/package/ihaskell-$ihaskell/ihaskell.cabal" \
          | sed -nE 's/^[[:space:]]*ghc[[:space:]]+(>=[0-9.]+[[:space:]]*&&[[:space:]]*<[0-9.]+).*/\1/p' | head -1)
[[ "$bound" =~ ^\>=([0-9.]+)[[:space:]]*\&\&[[:space:]]*\<([0-9.]+)$ ]] \
    || { echo "error: no 'ghc >=X && <Y' bound in ihaskell-$ihaskell.cabal" >&2; exit 1; }
lower="${BASH_REMATCH[1]}" upper="${BASH_REMATCH[2]}"

ghcs=$(bash "$ROOT/tools/ghc/tracked.sh")
found=false
for ghc in $ghcs; do
    if ! cb_version_lt "$ghc" "$lower" && ! cb_version_lt "$ghc" "$TRACK_FROM_GHC" \
            && cb_version_lt "$ghc" "$upper"; then
        echo "$ihaskell-ghc$ghc"; found=true
    fi
done
$found || { echo "error: no tracked GHC within ihaskell-$ihaskell's ghc $bound" >&2; exit 1; }
