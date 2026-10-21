#!/usr/bin/env bash
# GHC installed by ghcup, moved to /opt/ghc/ghc-<version>, then smoke-tested there.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "error: version must look like 9.12.4, got '$VERSION'" >&2; exit 1; }
PREFIX="/opt/ghc/ghc-$VERSION"

# What ghcup's GHC install (configure) and a first compile need.
cb_apt build-essential gzip libgmp-dev zlib1g-dev libtinfo6 libffi-dev libncurses-dev

echo "==> Installing GHC $VERSION with ghcup"
export GHCUP_INSTALL_BASE_PREFIX="$WORK/ghcup" GHCUP_SKIP_UPDATE_CHECK=1 \
       BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1
cb_fetch https://get-ghcup.haskell.org "$WORK/get-ghcup.sh"
ghcup="$WORK/ghcup/.ghcup/bin/ghcup"
{ bash "$WORK/get-ghcup.sh" && "$ghcup" install ghc "$VERSION"; } > "$WORK/ghcup.log" 2>&1 \
    || { tail -40 "$WORK/ghcup.log"; exit 1; }
"$ghcup" --version | sed 's/^/ghcup:        /' >> "$BUILD_NOTES"

# Only the wrapper scripts in bin/ name the install prefix; lib/settings and the package
# database use paths relative to the libdir.
built="$WORK/ghcup/.ghcup/ghc/$VERSION"
rm -rf "$PREFIX" && mkdir -p "$(dirname "$PREFIX")"
mv "$built" "$PREFIX"
rm -rf "$WORK/ghcup"
grep -lr "$built" "$PREFIX/bin" | xargs sed -i "s|$built|$PREFIX|g"
if left=$(grep -rIl "$built" "$PREFIX"); then
    echo "error: files still name the build prefix $built:" >&2; echo "$left" >&2; exit 1
fi

echo "==> Testing"
cd "$WORK"
cat > hello.hs <<'HS'
import qualified Data.Map as M
main :: IO ()
main = print (M.toList (M.fromListWith (+) [(w, 1 :: Int) | w <- words "a b a c b a"]))
HS
"$PREFIX/bin/ghc" -O hello.hs -o hello > /dev/null
[[ "$(./hello)" == '[("a",3),("b",2),("c",1)]' ]] || { echo "error: compiled program printed: $(./hello)" >&2; exit 1; }
[[ "$("$PREFIX/bin/runghc" hello.hs)" == '[("a",3),("b",2),("c",1)]' ]] || { echo "error: runghc failed" >&2; exit 1; }
[[ "$(echo '1 + 2' | "$PREFIX/bin/ghci" -v0)" == 3 ]] || { echo "error: ghci failed" >&2; exit 1; }
"$PREFIX/bin/ghc-pkg" check
[[ "$("$PREFIX/bin/ghc" --numeric-version)" == "$VERSION" ]]

mv "$PREFIX"/* "$PKG_DIR"/
