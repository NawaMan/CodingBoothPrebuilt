#!/usr/bin/env bash
# GNU Make from its release tarball, configured as CodingBooth's make setup configures it:
# --prefix=/opt/make/make-<version>. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

cb_apt build-essential

tarball="make-$VERSION.tar.gz"
echo "==> Downloading $tarball"
cb_fetch_gnu "make/$tarball" "$WORK/$tarball"

echo "==> Building"
tar -xzf "$WORK/$tarball" -C "$WORK"
SRC="$WORK/make-$VERSION"
[[ -d "$SRC" ]] || { echo "error: $tarball has no make-$VERSION/ folder" >&2; exit 1; }
PREFIX="/opt/make/make-$VERSION"
STAGE="$WORK/stage"
( cd "$SRC" \
  && ./configure --prefix="$PREFIX" \
  && make -j"$(nproc)" \
  && make install DESTDIR="$STAGE" ) > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }
[[ -x "$STAGE$PREFIX/bin/make" ]] || { echo "error: make install left no $PREFIX/bin/make" >&2; exit 1; }

echo "==> Testing"
MAKE_BIN="$STAGE$PREFIX/bin/make"
# Only libc: the asset ships no list of packages to install beside it.
linked=$(ldd "$MAKE_BIN" | awk '$3 ~ /^\// { print $3 }' | while read -r lib; do
             dpkg -S "$(readlink -f "$lib")" 2>/dev/null || dpkg -S "$lib"
         done | cut -d: -f1 | LC_ALL=C sort -u | tr '\n' ' ')
[[ "$linked" == "libc6 " ]] || { echo "error: make links more than libc6: $linked" >&2; exit 1; }
got=$("$MAKE_BIN" --version | head -1)
[[ "$got" == "GNU Make $VERSION" ]] || { echo "error: make --version printed '$got'" >&2; exit 1; }
echo "$got"
# A two-step build with a pattern rule, run in parallel, then an up-to-date second run.
mkdir -p "$WORK/t"
printf 'int main(void) { return 0; }\n' > "$WORK/t/a.c"
printf 'int unused;\n' > "$WORK/t/b.c"
cat > "$WORK/t/Makefile" <<'MK'
OBJS := $(patsubst %.c,%.o,$(wildcard *.c))
all: prog
prog: $(OBJS) ; $(CC) -o $@ $^
%.o: %.c ; $(CC) -c -o $@ $<
MK
"$MAKE_BIN" -C "$WORK/t" -j2 > "$WORK/t/out1" 2>&1 || { cat "$WORK/t/out1"; echo "error: the test build failed" >&2; exit 1; }
"$WORK/t/prog" || { echo "error: the program the test Makefile built does not run" >&2; exit 1; }
"$MAKE_BIN" -C "$WORK/t" -q || { echo "error: a second run found the test build out of date" >&2; exit 1; }
echo "smoke tests passed"

cp -a "$STAGE$PREFIX/." "$PKG_DIR/"
cp "$SRC/COPYING" "$PKG_DIR/COPYING"
{
    echo "source:       https://ftp.gnu.org/gnu/make/$tarball"
    echo "sha256:       $(sha256sum "$WORK/$tarball" | awk '{print $1}')"
    echo "prefix:       $PREFIX"
    echo "compiler:     $(gcc --version | head -1)"
} >> "$BUILD_NOTES"
