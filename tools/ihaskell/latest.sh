#!/usr/bin/env bash
# Newest IHaskell on Hackage paired with the newest tracked GHC its cabal file allows:
# the last line of tracked.sh. Prints e.g. 0.13.0.0-ghc9.12.4.
#
# Not ghcup's "recommended" GHC: that is 9.10.3, and IHaskell 0.13 on it kills the kernel
# ("ARR_WORDS object entered") when the first cell to import Data.Map also calls
# insertWith/fromListWith -- the build's smoke test fails there on x86_64 and arm64.
# 9.8.4 and 9.12.4 pass. CodingBooth's haskell-nb-kernel setup pins its own GHC for the
# kernel, so bump that separately.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/tracked.sh" | tail -1
