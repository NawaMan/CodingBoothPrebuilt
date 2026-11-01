#!/usr/bin/env bash
# Elm from its release tag, built with cabal against a ghcup GHC (tool.conf), then used to
# compile a small application. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

export LANG=C.UTF-8 LC_ALL=C.UTF-8
cb_apt git
cb_install_ghc "$BUILD_GHC"

SRC="$WORK/elm"
echo "==> Cloning elm/compiler $VERSION"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" https://github.com/elm/compiler "$SRC"
# worker/ is the package site's own executable, not part of the compiler.
{
    echo "packages: ."
    echo "index-state: $INDEX_STATE"
    echo "allow-newer: $(printf 'elm:%s, ' $ALLOW_NEWER | sed 's/, $//')"
} > "$SRC/cabal.project"

echo "==> cabal build elm-$VERSION"
(cd "$SRC" && cabal build exe:elm) > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }
cp "$(cd "$SRC" && cabal list-bin exe:elm)" "$PKG_DIR/elm"
strip "$PKG_DIR/elm"
cp "$SRC/LICENSE" "$PKG_DIR/LICENSE"

echo "==> Testing"
libs_missing="$(ldd "$PKG_DIR/elm" | grep 'not found' || true)"
[[ -z "$libs_missing" ]] || { echo "error: missing libraries:" >&2; echo "$libs_missing" >&2; exit 1; }
got=$("$PKG_DIR/elm" --version)
[[ "$got" == "$VERSION" ]] || { echo "error: elm --version printed '$got'" >&2; exit 1; }

# A real build: elm fetches the packages from package.elm-lang.org into ELM_HOME.
app="$WORK/app"
mkdir -p "$app/src"
cat > "$app/elm.json" <<'EOF'
{
    "type": "application",
    "source-directories": [ "src" ],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": { "elm/browser": "1.0.2", "elm/core": "1.0.5", "elm/html": "1.0.0" },
        "indirect": { "elm/json": "1.1.3", "elm/time": "1.0.0", "elm/url": "1.0.0", "elm/virtual-dom": "1.0.3" }
    },
    "test-dependencies": { "direct": {}, "indirect": {} }
}
EOF
printf 'module Main exposing (main)\nimport Html\nmain = Html.text (String.fromInt (List.sum [ 1, 2, 3 ]))\n' > "$app/src/Main.elm"
export ELM_HOME="$WORK/elm-home"
(cd "$app" && "$PKG_DIR/elm" make src/Main.elm --optimize --output="$WORK/main.js")
grep -q '_Platform_export' "$WORK/main.js" || { echo "error: main.js is not an Elm program" >&2; exit 1; }
# And a type error, which must fail with elm's report rather than crash.
printf 'module Main exposing (main)\nimport Html\nmain = Html.text (1 + "a")\n' > "$app/src/Main.elm"
if out=$(cd "$app" && "$PKG_DIR/elm" make src/Main.elm --output=/dev/null 2>&1); then
    echo "error: elm accepted a type error" >&2; exit 1
fi
grep -q 'TYPE MISMATCH' <<< "$out" || { echo "error: unexpected elm output:" >&2; echo "$out" >&2; exit 1; }
echo "smoke tests passed"

{
    echo "source:       https://github.com/elm/compiler at $VERSION ($(git -C "$SRC" rev-parse --short HEAD))"
    echo "ghc:          $(ghc --numeric-version) (ghcup), cabal $(cabal --numeric-version), Hackage index-state $INDEX_STATE"
    echo "runtime libs: libgmp10 libtinfo6 zlib1g (apt)"
} >> "$BUILD_NOTES"
