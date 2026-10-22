#!/usr/bin/env bash
# HLint from Hackage, built with the GHC of the Stackage snapshot that ships this version
# (else ghcup's recommended one). Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

# happy (pulled in through ghc-lib-parser) cannot read its UTF-8 grammar under the C locale.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ghc=$(cb_build_ghc hlint "$STACKAGE_FROM_LTS")
cb_install_ghc "$ghc"

echo "==> cabal install hlint-$VERSION"
cabal install "hlint-$VERSION" --installdir="$WORK/bin" --install-method=copy \
      --overwrite-policy=always > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }
strip "$WORK/bin/hlint"
(cd "$WORK" && cabal get "hlint-$VERSION" > /dev/null)

cp "$WORK/bin/hlint" "$PKG_DIR/hlint"
cp -r "$WORK/hlint-$VERSION/data" "$PKG_DIR/data"
cp "$WORK/hlint-$VERSION/LICENSE" "$PKG_DIR/LICENSE"

echo "==> Testing"
# Without the cabal store, hlint must find data/ beside itself, as upstream's build does.
rm -rf "$CABAL_DIR/store"
printf 'main = print (map (\\x -> f x) [1])\n  where f x = (x)\n' > "$WORK/t.hs"
out=$("$PKG_DIR/hlint" "$WORK/t.hs" || true)
echo "$out" | sed 's/^/   /'
grep -q "Redundant bracket" <<< "$out" || { echo "error: hlint gave no hints" >&2; exit 1; }
"$PKG_DIR/hlint" --version
echo "smoke tests passed"

echo "ghc:          $(ghc --numeric-version) (ghcup), cabal $(cabal --numeric-version)" >> "$BUILD_NOTES"
