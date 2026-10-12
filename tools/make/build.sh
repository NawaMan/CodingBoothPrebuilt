#!/usr/bin/env bash
# GNU Make from the GPG-verified release tarball. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

PREFIX="${PREFIX_PATTERN//\{version\}/$VERSION}"

cb_apt build-essential gnupg

DL="$WORK/download"
mkdir -p "$DL"
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"

echo "==> Downloading make-$VERSION and verifying its signature"
cb_fetch_gnu gnu-keyring.gpg "$DL/gnu-keyring.gpg"
gpg --batch --quiet --import "$DL/gnu-keyring.gpg" 2>/dev/null
cb_fetch_gnu "make/make-$VERSION.tar.gz"     "$DL/make-$VERSION.tar.gz"
cb_fetch_gnu "make/make-$VERSION.tar.gz.sig" "$DL/make-$VERSION.tar.gz.sig"
gpg --batch --quiet --verify "$DL/make-$VERSION.tar.gz.sig" "$DL/make-$VERSION.tar.gz" 2>/dev/null \
    || { echo "error: bad signature on make-$VERSION.tar.gz" >&2; exit 1; }

tar -xzf "$DL/make-$VERSION.tar.gz" -C "$WORK"
SRC="$WORK/make-$VERSION"

echo "==> Building (prefix $PREFIX)"
cd "$SRC"
./configure --prefix="$PREFIX" > "$WORK/configure.log" 2>&1 \
    || { tail -50 "$WORK/configure.log"; exit 1; }
make -j"$(nproc)" > "$WORK/make.log" 2>&1 || { tail -80 "$WORK/make.log"; exit 1; }
make install DESTDIR="$WORK/root" > "$WORK/install.log" 2>&1 || { tail -40 "$WORK/install.log"; exit 1; }

echo "==> Testing"
MAKE_BIN="$WORK/root$PREFIX/bin/make"
"$MAKE_BIN" --version | head -1
"$MAKE_BIN" --version | head -1 | grep -qF "GNU Make $VERSION" \
    || { echo "error: built make does not report $VERSION" >&2; exit 1; }

T="$WORK/smoke"
mkdir -p "$T"
printf 'hello\n' > "$T/a.in"
cat > "$T/Makefile" <<'EOF'
%.out: %.in
	cp $< $@
all: a.out
	@grep -qx hello a.out && echo "smoke tests passed"
EOF
"$MAKE_BIN" -s -C "$T" all

strip "$MAKE_BIN"
cp -a "$WORK/root$PREFIX/." "$PKG_DIR/"
cp "$SRC/COPYING" "$PKG_DIR/"
{
    echo "prefix:       $PREFIX"
    echo "source:       make-$VERSION.tar.gz (GPG verified)"
    echo "compiler:     $(gcc --version | head -1)"
} >> "$BUILD_NOTES"
