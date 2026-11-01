#!/usr/bin/env bash
# HLS from its release tag, built with the tag's cabal.project against a ghcup GHC and laid
# out the way upstream's release bindists are (GNUmakefile's hls-ghc and bindist-ghc); then
# installed into that ghcup tree and run on a Template Haskell project.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

[[ "$VERSION" =~ ^([0-9.]+)-ghc([0-9.]+)$ ]] \
    || { echo "error: version must look like 2.14.0.0-ghc9.12.4, got '$VERSION'" >&2; exit 1; }
HLS_VERSION="${BASH_REMATCH[1]}"
GHC_VERSION="${BASH_REMATCH[2]}"

# happy (pulled in through ghc-lib-parser) cannot read its UTF-8 grammar under the C locale.
export LANG=C.UTF-8 LC_ALL=C.UTF-8

cb_apt git pkg-config
cb_install_ghc "$GHC_VERSION"

SRC="$WORK/hls"
echo "==> Cloning haskell/haskell-language-server $HLS_VERSION"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$HLS_VERSION" \
    https://github.com/haskell/haskell-language-server "$SRC"

install=(cabal install --project-file=cabal.project -w "ghc-$GHC_VERSION"
         --disable-tests --disable-benchmarks --disable-profiling -O2
         --installdir="$WORK/bin" --install-method=copy --overwrite-policy=always
         exe:haskell-language-server exe:haskell-language-server-wrapper)
# When cabal falls back to a Hackage mirror, the mirror can lack a few of the ~300 tarballs
# (403), and cabal gives up. Fetch those from Hackage itself into cabal's package cache.
echo "==> Downloading the dependencies"
for try in 1 2 3; do
    (cd "$SRC" && "${install[@]}" --only-download) > "$WORK/build.log" 2>&1 && break
    missing=$(sed -nE 's/^Failed to download ([^ ]+) .*/\1/p' "$WORK/build.log")
    (( try < 3 )) && [[ -n "$missing" ]] || { tail -40 "$WORK/build.log"; exit 1; }
    for pv in $missing; do
        echo "   $pv: not on the mirror, fetching it from hackage.haskell.org"
        mkdir -p "$CABAL_DIR/packages/hackage.haskell.org/${pv%-*}/${pv##*-}"
        cb_fetch "https://hackage.haskell.org/package/$pv/$pv.tar.gz" \
                 "$CABAL_DIR/packages/hackage.haskell.org/${pv%-*}/${pv##*-}/$pv.tar.gz"
    done
done
echo "==> cabal install haskell-language-server (GHC $GHC_VERSION)"
(cd "$SRC" && "${install[@]}") > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }

# The layout `make install` of upstream's bindist gives (bindist-ghc in GNUmakefile, then
# bindist/GNUmakefile.in), which is what ghcup unpacks into .ghcup/hls/<hls>/. The server
# links the dynamic RTS on purpose (its cabal file: that RTS decides how Template Haskell
# loads libraries), so its non-boot libraries ship beside it, found through $ORIGIN, and
# bin/haskell-language-server-<ghc> is upstream's wrapper script: it checks that the GHC it
# finds has the boot packages' ABIs this was built against, puts that GHC's libraries on
# LD_LIBRARY_PATH, and runs the server.
echo "==> Packaging the bindist layout"
cb_apt patchelf
exe_dir="lib/haskell-language-server-$HLS_VERSION/bin"
lib_dir="lib/haskell-language-server-$HLS_VERSION/lib/$GHC_VERSION"
mkdir -p "$PKG_DIR/bin" "$PKG_DIR/$exe_dir" "$PKG_DIR/$lib_dir"
install -m 755 "$WORK/bin/haskell-language-server" "$PKG_DIR/$exe_dir/haskell-language-server-$GHC_VERSION"
install -m 755 "$WORK/bin/haskell-language-server-wrapper" "$PKG_DIR/$exe_dir/haskell-language-server-wrapper"
strip -s "$PKG_DIR/$exe_dir"/*
find "$CABAL_DIR"/store/ghc-"$GHC_VERSION"* -type f -name '*.so' -exec install -m 755 {} "$PKG_DIR/$lib_dir/" \;
patchelf --force-rpath --set-rpath "\$ORIGIN/../lib/$GHC_VERSION" "$PKG_DIR/$exe_dir/haskell-language-server-$GHC_VERSION"
find "$PKG_DIR/$lib_dir" -name '*.so' -exec patchelf --force-rpath --set-rpath '$ORIGIN' {} \;
boot_pkgs=$("ghc-pkg-$GHC_VERSION" --global list --simple-output)
abi_hashes=$(for dep in $boot_pkgs; do printf '%s:' "$dep" && "ghc-pkg-$GHC_VERSION" field "$dep" abi --simple-output; done | tr '\n' ' ' | xargs)
# Upstream's install writes its absolute exe dir into the script; this one finds it from
# where the script really is, so the tree works wherever it is unpacked.
sed -e "s|^exedir=.*|exedir=\"\$(dirname \"\$(readlink -f \"\$0\")\")/../$exe_dir\"|" \
    -e "s/@@EXE_NAME@@/haskell-language-server-$GHC_VERSION/" \
    -e "s/@@GHC_VERSION@@/$GHC_VERSION/" \
    -e "s/@@BOOT_PKGS@@/$boot_pkgs/" \
    -e "s/@@ABI_HASHES@@/$abi_hashes/" \
    "$SRC/bindist/wrapper.in" > "$PKG_DIR/bin/haskell-language-server-$GHC_VERSION"
chmod 755 "$PKG_DIR/bin/haskell-language-server-$GHC_VERSION"
ln -s "../$exe_dir/haskell-language-server-wrapper" "$PKG_DIR/bin/haskell-language-server-wrapper"
cp "$SRC/LICENSE" "$PKG_DIR/LICENSE"

echo "==> Testing"
# With the sources and the cabal store gone, the server has only its own libraries and the
# GHC to go on.
rm -rf "$SRC" "$CABAL_DIR/store"
ghc_libs=$(for d in "$(ghc --print-libdir)"/*/; do printf '%s:' "$d"; done)
missing=$(LD_LIBRARY_PATH="$ghc_libs" ldd "$PKG_DIR/$exe_dir/haskell-language-server-$GHC_VERSION" | grep 'not found' || true)
[[ -z "$missing" ]] || { echo "error: missing libraries:" >&2; echo "$missing" >&2; exit 1; }
if ldd "$PKG_DIR/$exe_dir/haskell-language-server-wrapper" | grep -q libHS; then
    echo "error: haskell-language-server-wrapper links Haskell libraries dynamically" >&2; exit 1
fi
# Where CodingBooth's lsp--hls setup unpacks it.
mkdir -p "$WORK/ghcup/.ghcup/hls/$HLS_VERSION" && cp -a "$PKG_DIR/." "$WORK/ghcup/.ghcup/hls/$HLS_VERSION/"
bash "$(dirname "${BASH_SOURCE[0]}")/ghcup-link.sh" "$WORK/ghcup/.ghcup" "$HLS_VERSION" "$GHC_VERSION"
bash "$(dirname "${BASH_SOURCE[0]}")/smoke.sh" "$HLS_VERSION" "$GHC_VERSION"
echo "smoke tests passed"

echo "ghc:          $GHC_VERSION (ghcup), cabal $(cabal --numeric-version)" >> "$BUILD_NOTES"
echo "install:      unpack into <ghcup>/.ghcup/hls/$HLS_VERSION, then: ghcup set hls $HLS_VERSION" >> "$BUILD_NOTES"
