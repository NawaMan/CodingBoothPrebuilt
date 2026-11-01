#!/usr/bin/env bash
# Type-checks a small cabal project with a Template Haskell splice through
# haskell-language-server-wrapper, as an editor would start it. Needs ghc, cabal and the
# wrapper on PATH, with `ghcup set hls` done. Used by build.sh and verify.sh.
#   smoke.sh <hls-version> <ghc-version>
set -euo pipefail
hls="${1:?usage: smoke.sh <hls-version> <ghc-version>}"
ghc="${2:?usage: smoke.sh <hls-version> <ghc-version>}"

[[ "$(ghc --numeric-version)" == "$ghc" ]] \
    || { echo "error: ghc on PATH is $(ghc --numeric-version), not $ghc" >&2; exit 1; }
for exe in haskell-language-server-wrapper "haskell-language-server-$ghc"; do
    got=$("$exe" --numeric-version)
    [[ "$got" == "$hls" ]] || { echo "error: $exe --numeric-version printed '$got'" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src"
cat > "$work/th.cabal" <<'CABAL'
cabal-version: 2.4
name:          th
version:       0.1
executable th
  main-is:          Main.hs
  other-modules:    Gen
  hs-source-dirs:   src
  build-depends:    base, containers, template-haskell
  default-language: Haskell2010
CABAL
cat > "$work/src/Gen.hs" <<'HS'
module Gen (answer) where
import Language.Haskell.TH
import qualified Data.Map as M

answer :: Q Exp
answer = litE (integerL (fromIntegral (M.size (M.fromList [(n, ()) | n <- [1 .. 42 :: Int]]))))
HS
cat > "$work/src/Main.hs" <<'HS'
{-# LANGUAGE TemplateHaskell #-}
module Main (main) where
import Gen (answer)

main :: IO ()
main = print ($(answer) :: Int)
HS
cd "$work"

# HLS reports per file and exits nonzero when one fails. A server built against another
# build of this GHC loads nothing: "GHC ABIs don't match". Sets out and status.
check() {
    out=$(HOME="$work" timeout 900 haskell-language-server-wrapper typecheck "$1" 2>&1) && status=0 || status=$?
    if [[ "$out" == *"ABIs don't match"* ]]; then
        echo "$out" | tail -20 >&2; echo "error: HLS was built against another build of GHC $ghc" >&2; exit 1
    fi
}
check src/Main.hs
(( status == 0 )) && [[ "$out" == *"1 file worked, 0 files failed"* ]] \
    || { echo "$out" | tail -40 >&2; echo "error: HLS failed to type-check the Template Haskell splice" >&2; exit 1; }
echo "   typecheck src/Main.hs (Template Haskell): ok"

# And it really type-checks: a wrong type is reported (as a diagnostic; the exit status
# only counts files that could not be loaded).
sed -i 's/:: Int)/:: String)/' src/Main.hs
check src/Main.hs
# "Num String" up to GHC 9.12, "Num [Char]" from 9.14.
[[ "$out" == *DiagnosticSeverity_Error*"No instance for"*"Num "* ]] \
    || { echo "$out" | tail -40 >&2; echo "error: HLS did not report a type error" >&2; exit 1; }
echo "   typecheck of a type error: reported, as it should be"
