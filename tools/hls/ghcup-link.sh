#!/usr/bin/env bash
# After an asset is unpacked into <ghcup-dir>/hls/<hls>/, adds the versioned links that
# `ghcup install hls` makes in <ghcup-dir>/bin -- haskell-language-server-<ghc>~<hls> and
# haskell-language-server-wrapper-<hls>, which `ghcup set hls` looks for -- then sets it.
# What CodingBooth's lsp--hls setup does after unpacking. Used by build.sh and verify.sh.
#   ghcup-link.sh <ghcup-dir> <hls-version> <ghc-version>
set -euo pipefail
dir="${1:?usage: ghcup-link.sh <ghcup-dir> <hls-version> <ghc-version>}"
hls="${2:?}" ghc="${3:?}"

ln -sfn "../hls/$hls/bin/haskell-language-server-$ghc" "$dir/bin/haskell-language-server-$ghc~$hls"
ln -sfn "../hls/$hls/bin/haskell-language-server-wrapper" "$dir/bin/haskell-language-server-wrapper-$hls"
"$dir/bin/ghcup" set hls "$hls"
[[ "$(readlink -f "$dir/bin/haskell-language-server-$ghc")" == "$(readlink -f "$dir/hls/$hls/bin/haskell-language-server-$ghc")" ]] \
    || { ls -l "$dir/bin" >&2; echo "error: ghcup set hls $hls did not link haskell-language-server-$ghc" >&2; exit 1; }
