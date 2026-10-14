#!/usr/bin/env bash
# IHaskell kernel built with cabal against a ghcup GHC, then run on a real notebook.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

[[ "$VERSION" =~ ^([0-9.]+)-ghc([0-9.]+)$ ]] \
    || { echo "error: version must look like 0.13.0.0-ghc9.10.3, got '$VERSION'" >&2; exit 1; }
IHASKELL_VERSION="${BASH_REMATCH[1]}"
GHC_VERSION="${BASH_REMATCH[2]}"
PREFIX="${PREFIX_PATTERN//\{version\}/$VERSION}"

# happy (pulled in through ghc-lib-parser) cannot read its UTF-8 grammar under the C locale.
export LANG=C.UTF-8 LC_ALL=C.UTF-8

cb_apt git pkg-config libmagic-dev libzmq3-dev python3 python3-venv
cb_install_ghc "$GHC_VERSION"

# The store goes straight into the final prefix: the binary finds its data files there.
echo "==> cabal install ihaskell-$IHASKELL_VERSION into $PREFIX"
rm -rf "$PREFIX" && mkdir -p "$PREFIX/bin"
cabal --store-dir="$PREFIX/store" install "ihaskell-$IHASKELL_VERSION" \
      --installdir="$PREFIX/bin" --install-method=copy --overwrite-policy=always \
      > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }
strip "$PREFIX/bin/ihaskell"

# The executable links every Haskell library statically; of the store only the data
# files are used at run time.
find "$PREFIX/store" -mindepth 1 -maxdepth 1 ! -name 'ghc-*' -exec rm -rf {} +
find "$PREFIX"/store/ghc-* -mindepth 1 -maxdepth 1 ! -type d -exec rm -f {} +
find "$PREFIX"/store/ghc-* -mindepth 2 -maxdepth 2 ! -name share -exec rm -rf {} +
find "$PREFIX"/store/ghc-* -mindepth 1 -maxdepth 1 -type d -empty -delete

echo "==> Testing"
libs_missing="$(ldd "$PREFIX/bin/ihaskell" | grep 'not found' || true)"
[[ -z "$libs_missing" ]] || { echo "error: missing libraries:" >&2; echo "$libs_missing" >&2; exit 1; }

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet jupyter_client nbclient nbformat
export PATH="$WORK/venv/bin:$PATH"   # ihaskell install looks for a jupyter command
"$PREFIX/bin/ihaskell" install --ghclib "$(ghc --print-libdir)" --prefix "$WORK/venv"
python3 - <<'PY'
import nbformat, nbclient
cells = {
    "1 + 1": "2",
    'import qualified Data.Map as M\nM.fromList [(1, "a")]': 'fromList [(1,"a")]',
    "data T = A | B deriving Show\n[A, B]": "[A,B]",
    "f :: Int -> Int\nf x = x * 2\nmap f [1 .. 5]": "[2,4,6,8,10]",
    # GHC 9.10.3 + IHaskell 0.13 kills the kernel here ("ARR_WORDS object entered").
    'M.fromListWith (+) [("a", 1 :: Int), ("b", 1), ("a", 1)]': 'fromList [("a",2),("b",1)]',
    'M.insertWith (+) "a" (1 :: Int) M.empty': 'fromList [("a",1)]',
}
nb = nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(c) for c in cells])
nbclient.NotebookClient(nb, kernel_name="haskell", timeout=300).execute()
for cell, want in zip(nb.cells, cells.values()):
    got = [o.get("data", {}).get("text/plain") for o in cell.outputs]
    assert got == [want], f"{cell.source!r}: expected {want!r}, got {cell.outputs!r}"
    print(f"   {cell.source.splitlines()[-1]!r} => {want}")
PY
echo "smoke tests passed"

cp -a "$PREFIX/." "$PKG_DIR/"
cp "$(ls -d "$PREFIX"/store/ghc-*/"ihaskell-$IHASKELL_VERSION"-[0-9a-f]*/share/doc/LICENSE | head -1)" "$PKG_DIR/LICENSE"
{
    echo "ghc:          $GHC_VERSION (ghcup), cabal $(cabal --numeric-version)"
    echo "prefix:       $PREFIX (extract here; the paths are baked in)"
    echo "runtime libs: libgmp10 libtinfo6 libffi8 libzmq5 libmagic1 (apt)"
} >> "$BUILD_NOTES"
