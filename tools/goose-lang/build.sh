#!/usr/bin/env bash
# goose-lang from its release tag, built and tested the way upstream's release workflow
# (.github/workflows/release.yml) builds its linux x64 archive: configure with every
# blessed package compiled in, build, package with scripts/package_release.py, move the
# build tree away, then run the samples with the packaged compiler.
# Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

# git: the packaging copies the tag's tracked files, and configure fetches the blessed
# packages. The SDL3 libraries are what the gfx package builds against, as upstream's
# list; Mesa's lavapipe is a Vulkan device for the gfx samples to draw on, off screen.
cb_apt build-essential cmake git python3 \
    libasound2-dev libpulse-dev libaudio-dev libfribidi-dev libjack-dev libsndio-dev \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev \
    libxss-dev libxtst-dev libxkbcommon-dev libdrm-dev libgbm-dev libdbus-1-dev \
    libibus-1.0-dev libudev-dev libthai-dev libpipewire-0.3-dev libwayland-dev \
    libdecor-0-dev liburing-dev mesa-vulkan-drivers libvulkan1

SRC="$WORK/goose"
echo "==> Cloning aardappel/goose v$VERSION"
git -c advice.detachedHead=false clone -q --depth 1 --branch "v$VERSION" https://github.com/aardappel/goose "$SRC"

log="$WORK/build.log"
step() {
    echo "==> $1"; shift
    (cd "$SRC" && "$@") > "$log" 2>&1 || { tail -80 "$log"; exit 1; }
}
step "Configuring" cmake -B build -DCMAKE_BUILD_TYPE=Release -DGOOSE_BUILTIN_LIBS=all "-DGOOSE_VERSION=v$VERSION"
step "Building"    cmake --build build --config Release --parallel
step "Packaging"   python3 scripts/package_release.py --build build --config Release --out "$WORK/release"

echo "==> Testing"
# With its build tree gone, the compiler has to find the standard library, TinyCC's runtime
# and the packages beside itself, as an unpacked release does.
mv "$SRC/build" "$SRC/build-moved"
# `goose version` names the runtime, not the release: "goose runtime <id>".
runtime=$("$WORK/release/goose" version 2>&1 | head -1)
[[ "$runtime" =~ ^goose\ runtime\ [0-9a-f]+$ ]] || { echo "error: goose version printed '$runtime'" >&2; exit 1; }
# Every sample, in-process through TinyCC and as a native executable through gcc.
step "Running the samples" python3 samples/run_samples.py --exe "$WORK/release/goose"
tail -5 "$log"
# A compiler that cannot find a package it has compiled in fetches and builds it into
# GOOSE_HOME instead, which passes the samples but is not a working release.
if [[ -e "$SRC/build/goose-home/pkg" ]]; then
    echo "error: the release fetched packages it has compiled in:" >&2
    ls -R "$SRC/build/goose-home/pkg" | head -20 >&2
    exit 1
fi
echo "smoke tests passed"

cp -a "$WORK/release/." "$PKG_DIR/"
{
    echo "source:       https://github.com/aardappel/goose at v$VERSION ($(git -C "$SRC" rev-parse --short HEAD))"
    echo "runtime:      ${runtime#goose runtime }"
    echo "compiler:     $(g++ --version | head -1), cmake $(cmake --version | head -1 | awk '{print $3}')"
} >> "$BUILD_NOTES"
