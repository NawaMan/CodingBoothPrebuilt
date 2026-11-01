#!/usr/bin/env bash
# ghcup's recommended and latest HLS, each paired with every tracked GHC (../ghc/tracked.sh)
# of a series its cabal file's tested-with names. Prints e.g. 2.14.0.0-ghc9.12.4, one per
# line, oldest first.
set -euo pipefail
source "$ROOT/lib/common.sh"

# The HLS versions tagged recommended or latest in ghcup's metadata, which is what
# `ghcup install hls` (CodingBooth's lsp--hls default) picks.
metadata=$(curl -fsSL --retry 3 https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml)
hlss=$(awk '
        /^ghcupDownloads:/      { downloads = 1; next }
        !downloads              { next }
        /^  [A-Za-z]/           { section = $1 }
        section != "HLS:"       { next }
        /^      [0-9][0-9.]*:$/ { version = $1; sub(/:$/, "", version) }
        /^ *- (Recommended|Latest)$/ { print version }' <<< "$metadata" | sort -uV)
[[ -n "$hlss" ]] || { echo "error: no recommended or latest HLS in ghcup metadata" >&2; exit 1; }

ghcs=$(bash "$ROOT/tools/ghc/tracked.sh")
for hls in $hlss; do
    # e.g. "tested-with: GHC == {9.14.1, 9.12.2, 9.10.3}": the GHC series this release supports.
    series=$(curl -fsSL --retry 3 "https://hackage.haskell.org/package/haskell-language-server-$hls/haskell-language-server.cabal" \
               | sed -nE 's/^tested-with:[[:space:]]*GHC[[:space:]]*==[[:space:]]*\{?([0-9., ]+)\}?.*/\1/p' \
               | tr -s ', ' '\n' | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')
    [[ -n "$series" ]] || { echo "error: no 'tested-with: GHC == ...' in haskell-language-server-$hls.cabal" >&2; exit 1; }
    for ghc in $ghcs; do
        if grep -qxF "${ghc%.*}" <<< "$series"; then echo "$hls-ghc$ghc"; fi
    done
done | sort -V
