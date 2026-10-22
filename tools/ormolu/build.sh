#!/usr/bin/env bash
# Ormolu from Hackage, built with the GHC of the Stackage snapshot that ships this version
# (else ghcup's recommended one). Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

export LANG=C.UTF-8 LC_ALL=C.UTF-8
ghc=$(cb_build_ghc ormolu "$STACKAGE_FROM_LTS")
cb_install_ghc "$ghc"

echo "==> cabal install ormolu-$VERSION"
cabal install "ormolu-$VERSION" --installdir="$WORK/bin" --install-method=copy \
      --overwrite-policy=always > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }
strip "$WORK/bin/ormolu"
(cd "$WORK" && cabal get "ormolu-$VERSION" > /dev/null)

cp "$WORK/bin/ormolu" "$PKG_DIR/ormolu"
cp "$WORK/ormolu-$VERSION/LICENSE.md" "$PKG_DIR/LICENSE.md" 2>/dev/null \
    || cp "$WORK/ormolu-$VERSION/LICENSE" "$PKG_DIR/LICENSE"

echo "==> Testing"
rm -rf "$CABAL_DIR/store"
printf 'main = do\n  print (map (\\x -> f x) [1])\n  where f x = x\n' > "$WORK/t.hs"
want=$'main = do\n  print (map (\\x -> f x) [1])\n  where\n    f x = x'
got=$("$PKG_DIR/ormolu" "$WORK/t.hs")
[[ "$got" == "$want" ]] || { echo "error: unexpected formatting:" >&2; echo "$got" >&2; exit 1; }
"$PKG_DIR/ormolu" --version | head -1
echo "smoke tests passed"

echo "ghc:          $(ghc --numeric-version) (ghcup), cabal $(cabal --numeric-version)" >> "$BUILD_NOTES"
