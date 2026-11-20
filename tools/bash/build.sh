#!/usr/bin/env bash
# GNU Bash from its release tarball, configured as CodingBooth's bash setup configures it:
# --prefix=/opt/bash/bash-<version> --without-bash-malloc. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] \
    || { echo "error: not a bash version: '$VERSION' (X.Y or X.Y.Z)" >&2; exit 1; }
MAJOR="${BASH_REMATCH[1]}" MINOR="${BASH_REMATCH[2]}"

# bison: an old release's parse.y is newer than its y.tab.c. autotools-dev: a current
# config.guess, for a release older than the CPU it is built on.
cb_apt build-essential bison libncurses-dev autotools-dev

tarball="bash-$VERSION.tar.gz"
echo "==> Downloading $tarball"
cb_fetch_gnu "bash/$tarball" "$WORK/$tarball"

echo "==> Building"
tar -xzf "$WORK/$tarball" -C "$WORK"
SRC="$WORK/bash-$VERSION"
[[ -d "$SRC" ]] || { echo "error: $tarball has no bash-$VERSION/ folder" >&2; exit 1; }
PREFIX="/opt/bash/bash-$VERSION"
STAGE="$WORK/stage"

# Keep in step with CodingBooth's variants/base/setups/bash--setup.sh. GCC 15 (Ubuntu
# 26.04) defaults to C23: Bash 3.x is K&R C and needs gnu89 plus -fpermissive, Bash before
# 5.3 needs gnu17, 5.3 compiles as C23.
cflags=""
if (( MAJOR < 4 )); then
    cflags="-std=gnu89 -fpermissive"
elif (( MAJOR < 5 || (MAJOR == 5 && MINOR < 3) )); then
    cflags="-std=gnu17"
fi
if [[ -n "$cflags" ]]; then
    export CFLAGS="$cflags" CFLAGS_FOR_BUILD="$cflags"
fi
# Bash 3.2 races under make -j (two jobs write support/newversion.h).
jobs="$(nproc)"; (( MAJOR < 4 )) && jobs=1
(
    cd "$SRC"
    # Through sh: not every release ships config.guess executable.
    if ! sh support/config.guess >/dev/null 2>&1; then
        cp /usr/share/misc/config.guess /usr/share/misc/config.sub support/
    fi
    ./configure --prefix="$PREFIX" --without-bash-malloc \
      && make -j"$jobs" \
      && make install DESTDIR="$STAGE"
) > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }
[[ -x "$STAGE$PREFIX/bin/bash" ]] || { echo "error: make install left no $PREFIX/bin/bash" >&2; exit 1; }

echo "==> Testing"
BASH_BIN="$STAGE$PREFIX/bin/bash"
# Only libc and libtinfo: the asset ships no list of packages to install beside it.
linked=$(ldd "$BASH_BIN" | awk '$3 ~ /^\// { print $3 }' | while read -r lib; do
             dpkg -S "$(readlink -f "$lib")" 2>/dev/null || dpkg -S "$lib"
         done | cut -d: -f1 | LC_ALL=C sort -u | tr '\n' ' ')
case "$linked" in
    "libc6 "|"libc6 libtinfo6 ") ;;
    *) echo "error: bash links more than libc6 and libtinfo6: $linked" >&2; exit 1 ;;
esac
got=$("$BASH_BIN" -c 'printf %s "$BASH_VERSION"'); got="${got%%\(*}"
case "$got" in
    "$VERSION"|"$VERSION".*) ;;
    *) echo "error: the built bash reports $got, wanted $VERSION" >&2; exit 1 ;;
esac
"$BASH_BIN" --version | head -1
# Arrays, an associative array, a process substitution, a pipeline's status and a regex.
cat > "$WORK/t.sh" <<'SH'
set -eu
declare -A count=()
while read -r word; do count[$word]=$(( ${count[$word]:-0} + 1 )); done < <(printf '%s\n' a b a c b a)
words=(x y z)
[[ "release-${words[1]}" =~ ^release-([a-z])$ ]]
false | true
echo "${count[a]}${count[b]}${count[c]} ${#words[@]} ${BASH_REMATCH[1]} ${PIPESTATUS[0]}"
SH
got=$("$BASH_BIN" "$WORK/t.sh") || { echo "error: the test script failed" >&2; exit 1; }
[[ "$got" == "321 3 y 1" ]] || { echo "error: the test script printed '$got'" >&2; exit 1; }
# Interactive mode goes through readline and the terminal library.
got=$(printf 'echo "ok $((6 * 7))"\nexit\n' | TERM=dumb "$BASH_BIN" --norc -i 2>/dev/null | tail -1)
[[ "$got" == "ok 42" ]] || { echo "error: an interactive bash printed '$got'" >&2; exit 1; }
echo "smoke tests passed"

cp -a "$STAGE$PREFIX/." "$PKG_DIR/"
cp "$SRC/COPYING" "$PKG_DIR/COPYING"
{
    echo "source:       https://ftp.gnu.org/gnu/bash/$tarball"
    echo "sha256:       $(sha256sum "$WORK/$tarball" | awk '{print $1}')"
    echo "prefix:       $PREFIX"
    echo "cflags:       ${cflags:-(compiler default)}"
    echo "compiler:     $(gcc --version | head -1)"
} >> "$BUILD_NOTES"
