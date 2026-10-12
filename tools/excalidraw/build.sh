#!/usr/bin/env bash
# Excalidraw self-hosted app build from a release tag. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

cb_apt git
cb_install_node "$NODE_MAJOR"
npm install -g --silent yarn

SRC="$WORK/excalidraw"
echo "==> Cloning excalidraw v$VERSION"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v$VERSION" "$UPSTREAM.git" "$SRC"
COMMIT="$(git -C "$SRC" rev-parse HEAD)"

cd "$SRC"
echo "==> yarn install"
yarn install --frozen-lockfile --silent --network-timeout 600000
echo "==> yarn build:app:docker"
NODE_ENV=production yarn build:app:docker > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }

echo "==> Testing"
OUT=excalidraw-app/build
[[ -f "$OUT/index.html" ]] || { echo "error: $OUT/index.html missing" >&2; exit 1; }
[[ -n "$(find "$OUT" -name '*.js' -print -quit)" ]] || { echo "error: no JavaScript in $OUT" >&2; exit 1; }
echo "smoke tests passed"

cp -a "$OUT/." "$PKG_DIR/"
cp LICENSE "$PKG_DIR/LICENSE"
{
    echo "source:       excalidraw v$VERSION ($COMMIT)"
    echo "node:         $(node --version), yarn $(yarn --version)"
} >> "$BUILD_NOTES"
