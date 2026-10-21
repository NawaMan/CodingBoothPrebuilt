#!/usr/bin/env bash
# Newest IHaskell on Hackage, paired with GHC 9.12.4. Prints e.g. 0.13.0.0-ghc9.12.4.
#
# Not ghcup's "recommended" GHC: that is 9.10.3, and IHaskell 0.13 on it kills the kernel
# ("ARR_WORDS object entered") when the first cell to import Data.Map also calls
# insertWith/fromListWith -- the build's smoke test fails there on x86_64 and arm64.
# 9.8.4 and 9.12.4 pass. CodingBooth's haskell-nb-kernel setup installs this same GHC
# for the kernel, so move both together.
set -euo pipefail

ghc=9.12.4

ihaskell=$(curl -fsSL --retry 3 -H 'Accept: application/json' \
    https://hackage.haskell.org/package/ihaskell/preferred | jq -er '."normal-version"[0]')

echo "$ihaskell-ghc$ghc"
