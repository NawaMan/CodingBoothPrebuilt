#!/usr/bin/env bash
# HeidiSQL's Qt6 build from its release tag, the way upstream's release workflow
# (.github/workflows/lazarus.yaml) builds it: Lazarus LAZARUS_VERSION with HeidiSQL's patches,
# `lazbuild -B --bm=Release --ws=qt6` through lazbuild-with-buildnr.sh, packaged as its
# tar-qt6 target lays it out. Called by ../../build.sh.
#
# Upstream installs Lazarus from SourceForge .debs and libQt6Pas from davidbannon/libqt6pas.
# Here both come from the Lazarus source at the same release, built with Ubuntu's FPC
# against Ubuntu's Qt6: libQt6Pas is Lazarus' own cbindings, so it always matches the LCL
# that calls it, and it ships inside the package instead of as a .deb Ubuntu does not have.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

# git: lazbuild-with-buildnr.sh numbers the build by the tag's commit count. xvfb, xdotool:
# the smoke test opens the window on a virtual X display.
cb_apt build-essential fpc git patchelf qt6-base-dev qmake6 qt6-qpa-plugins \
    xvfb xauth xdotool libqt6widgets6 libqt6gui6 libqt6core6t64

log="$WORK/build.log"
step() {
    echo "==> $1"; shift
    "$@" > "$log" 2>&1 || { tail -80 "$log"; exit 1; }
}

SRC="$WORK/heidisql"
echo "==> Cloning HeidiSQL/HeidiSQL v$VERSION"
# The commit history, without old trees and files, is all the build number needs.
git -c advice.detachedHead=false clone -q --filter=blob:none --branch "v$VERSION" \
    https://github.com/HeidiSQL/HeidiSQL "$SRC"
patches=("$SRC/extra/lazarus-patches/$LAZARUS_VERSION"/*.patch)
[[ -f "${patches[0]}" ]] || { echo "error: v$VERSION has no extra/lazarus-patches/$LAZARUS_VERSION" >&2; exit 1; }

LAZ="$WORK/lazarus"
echo "==> Fetching Lazarus $LAZARUS_VERSION"
cb_fetch "https://gitlab.com/freepascal.org/lazarus/lazarus/-/archive/lazarus_${LAZARUS_VERSION//./_}/lazarus-lazarus_${LAZARUS_VERSION//./_}.tar.gz" "$WORK/lazarus.tar.gz"
mkdir -p "$LAZ" && tar -xzf "$WORK/lazarus.tar.gz" -C "$LAZ" --strip-components=1
echo "==> Applying HeidiSQL's Lazarus patches"
for p in "${patches[@]}"; do
    patch -d "$LAZ" -p1 --dry-run -s < "$p" && patch -d "$LAZ" -p1 -s < "$p"
done

# libQt6Pas, the C++ layer the LCL's Qt6 widgetset calls. FPC links it by name, so put its
# folder on FPC's library path (the container's /etc/fpc.cfg is throwaway).
QTPAS="$LAZ/lcl/interfaces/qt6/cbindings"
step "Building libQt6Pas" bash -c "cd '$QTPAS' && qmake6 Qt6Pas.pro && make -j$(nproc)"
echo "-Fl$QTPAS" >> /etc/fpc.cfg

step "Building lazbuild" make -C "$LAZ" lazbuild
LAZBUILD=("$LAZ/lazbuild" --lazarusdir="$LAZ" --primary-config-path="$WORK/lazarus-config")
step "Building HeidiSQL" bash "$SRC/lazbuild-with-buildnr.sh" "${LAZBUILD[@]}" -B --bm=Release --ws=qt6 "$SRC/heidisql.lpi"
buildnr=$(git -C "$SRC" rev-list --count HEAD)

# upstream's tar-qt6 layout, plus libQt6Pas. The Release mode passes macOS' Frameworks
# rpath on every OS; point it at lib/ instead.
mkdir -p "$PKG_DIR/locale" "$PKG_DIR/lib"
cp "$SRC/out/heidisql" "$PKG_DIR/heidisql"
cp "$SRC/extra/locale/"*.mo "$PKG_DIR/locale/"
cp "$SRC/extra/ini/"*.ini "$PKG_DIR/"
cp "$SRC/res/deb-package-icon.png" "$PKG_DIR/heidisql.png"
cp "$SRC/README.md" "$SRC/LICENSE" "$PKG_DIR/"
cp -P "$QTPAS"/libQt6Pas.so.6* "$PKG_DIR/lib/"
patchelf --set-rpath '$ORIGIN/lib' "$PKG_DIR/heidisql"

echo "==> Testing"
missing="$(ldd "$PKG_DIR/heidisql" | grep 'not found' || true)"
[[ -z "$missing" ]] || { echo "error: missing libraries:" >&2; echo "$missing" >&2; exit 1; }
ldd "$PKG_DIR/heidisql" | grep -q "$PKG_DIR/lib/libQt6Pas.so.6" \
    || { echo "error: heidisql does not load the libQt6Pas beside it" >&2; ldd "$PKG_DIR/heidisql" >&2; exit 1; }
# Start it on a virtual display, from a symlink as a PATH link would, and wait for its
# session manager: a window means the LCL, Qt6 and its own files all came up.
ln -s "$PKG_DIR/heidisql" "$WORK/heidisql-link"
export HOME="$WORK/home" QT_QPA_PLATFORM=xcb
mkdir -p "$HOME"
xvfb-run -a bash -c '
    "$1" > "$2" 2>&1 & pid=$!
    for _ in $(seq 60); do
        win=$(xdotool search --pid "$pid" --onlyvisible --name . 2>/dev/null | head -1)
        [[ -n "$win" ]] && { echo "   window: $(xdotool getwindowname "$win")"; kill "$pid"; exit 0; }
        kill -0 "$pid" 2>/dev/null || { echo "error: heidisql exited before showing a window" >&2; cat "$2" >&2; exit 1; }
        sleep 1
    done
    echo "error: heidisql showed no window within 60 seconds" >&2; cat "$2" >&2; kill "$pid"; exit 1
' _ "$WORK/heidisql-link" "$WORK/run.log"
echo "smoke tests passed"

qt=$(dpkg-query -W -f='${Version}' libqt6core6t64)
{
    echo "source:       https://github.com/HeidiSQL/HeidiSQL at v$VERSION ($(git -C "$SRC" rev-parse --short HEAD), build $buildnr)"
    echo "compiler:     Lazarus $LAZARUS_VERSION with HeidiSQL's patches, $(fpc -iV | head -1 | sed 's/^/FPC /'), Qt ${qt%%+*} (Ubuntu)"
    echo "libQt6Pas:    lib/, from Lazarus $LAZARUS_VERSION's lcl/interfaces/qt6/cbindings"
    echo "runtime libs: libqt6widgets6 libqt6gui6 libqt6core6t64 libqt6printsupport6 qt6-qpa-plugins (apt); database"
    echo "              clients as needed: libmariadb3 libpq5 libsqlite3-0 libsybdb5 libfbclient2"
} >> "$BUILD_NOTES"
