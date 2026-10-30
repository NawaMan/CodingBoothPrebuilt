#!/usr/bin/env bash
# Nim from its release source tarball, built the way nim-lang's release script
# (github.com/nim-lang/nightlies, build-release.sh) builds the x86_64 binary: the bundled
# C sources, koch boot, koch tools, koch docs, then the build leftovers removed.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

# git: koch tools and koch docs clone atlas and the official packages (pkgs/).
cb_apt build-essential git

echo "==> Fetching nim-$VERSION.tar.xz"
cb_fetch "https://nim-lang.org/download/nim-$VERSION.tar.xz" "$WORK/nim.tar.xz"
tar -xJf "$WORK/nim.tar.xz" -C "$WORK"
SRC="$WORK/nim-$VERSION"
[[ -d "$SRC" ]] || { echo "error: nim-$VERSION.tar.xz has no nim-$VERSION/ folder" >&2; exit 1; }

# Keep koch and nim away from root's config and cache.
export XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/nimcache"
export PATH="$SRC/bin:$PATH"
log="$WORK/build.log"
step() {
    echo "==> $1"; shift
    (cd "$SRC" && "$@") > "$log" 2>&1 || { tail -80 "$log"; exit 1; }
}
step "Building the C-sources compiler" make "-j$(nproc)" CC=gcc
step "Building koch"                   nim c koch
step "Building the compiler"           ./koch boot -d:release --skipUserCfg:off
step "Building the tools"              ./koch tools -d:release
step "Building the docs"               ./koch --localdocs docs -d:release --doccmd:skip

# The same cleanup as nim-lang's release script, so the tree matches upstream's.
rm -rf "$SRC/build"   # koch docs clones its deps here
find "$SRC" -mindepth 1 \( \
        -name .git -prune -o -name c_code -prune -o -name nimcache -prune -o -name .nimcache -prune -o -name web -prune -o \
        -name build.sh -o -name 'build*.bat' -o -name makefile -o -name '*.o' -o \
        -path '*/compiler/nim' -o -path '*/compiler/nim?' \
    \) -exec rm -rf '{}' +
strip "$SRC"/bin/* 2>/dev/null || true   # bin/ also holds scripts (nim-gdb)
cp -a "$SRC/." "$PKG_DIR/"
rm -rf "$SRC" "$XDG_CACHE_HOME"

echo "==> Testing"
NIM="$PKG_DIR/bin/nim"
want="Nim Compiler Version $VERSION [Linux: arm64]"
[[ "$(cb_arch)" == arm64 ]] || want="Nim Compiler Version $VERSION [Linux: amd64]"
got=$("$NIM" --version | head -1)
[[ "$got" == "$want"* ]] || { echo "error: expected '$want', got '$got'" >&2; exit 1; }
for t in nimble atlas nimsuggest nimgrep nimpretty; do
    [[ -x "$PKG_DIR/bin/$t" ]] || { echo "error: bin/$t was not built" >&2; exit 1; }
done
# nimgrep is not run: it dlopens PCRE1 (libpcre3), which Ubuntu 26.04 no longer ships.
for t in nimble atlas nimsuggest nimpretty; do
    "$PKG_DIR/bin/$t" --version > /dev/null 2>&1 || { "$PKG_DIR/bin/$t" --version; echo "error: $t --version failed" >&2; exit 1; }
done
mkdir -p "$WORK/t"
cat > "$WORK/t/hello.nim" <<'NIM'
import std/[json, strutils, tables, sequtils]
var counts = initCountTable[string]()
for w in "a b a c b a".splitWhitespace: counts.inc w
let j = %*{"top": counts.largest.key, "n": toSeq(1..3).mapIt(it * it)}
echo j
NIM
want='{"top":"a","n":[1,4,9]}'
for mode in "" -d:release; do
    got=$("$NIM" c -r --hints:off $mode --nimcache:"$WORK/t/cache" "$WORK/t/hello.nim")
    [[ "$got" == "$want" ]] || { echo "error: hello.nim $mode printed '$got'" >&2; exit 1; }
done
printf 'proc  f( x:int ):int=x+1\n' > "$WORK/t/fmt.nim"
"$PKG_DIR/bin/nimpretty" --out:"$WORK/t/out.nim" "$WORK/t/fmt.nim"
got=$(cat "$WORK/t/out.nim")
[[ "$got" == "proc f(x: int): int = x+1" ]] || { echo "error: nimpretty printed '$got'" >&2; exit 1; }
echo "smoke tests passed"

{
    echo "source:       https://nim-lang.org/download/nim-$VERSION.tar.xz"
    echo "compiler:     $(gcc --version | head -1)"
} >> "$BUILD_NOTES"
