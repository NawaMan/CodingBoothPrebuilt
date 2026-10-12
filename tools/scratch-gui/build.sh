#!/usr/bin/env bash
# scratch-gui production webpack build from a release tag. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"

cb_apt git
cb_install_node "$NODE_MAJOR"

SRC="$WORK/scratch-gui"
echo "==> Cloning scratch-gui v$VERSION"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v$VERSION" "$UPSTREAM.git" "$SRC"
COMMIT="$(git -C "$SRC" rev-parse HEAD)"

cd "$SRC"
echo "==> npm ci"
npm ci --no-audit --no-fund --loglevel=error
echo "==> npm run build"
NODE_ENV=production npm run build > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }

echo "==> Testing"
[[ -f build/index.html ]] || { echo "error: build/index.html missing" >&2; exit 1; }
ls build/*.js >/dev/null 2>&1 || { echo "error: no JavaScript bundles in build/" >&2; exit 1; }
echo "smoke tests passed"

cp -a build/. "$PKG_DIR/"
cp LICENSE "$PKG_DIR/LICENSE"
cat > "$PKG_DIR/SOURCE.txt" <<EOF
Built from $UPSTREAM
tag v$VERSION, commit $COMMIT
Source: $UPSTREAM/tree/v$VERSION
EOF
{
    echo "source:       scratch-gui v$VERSION ($COMMIT)"
    echo "node:         $(node --version)"
} >> "$BUILD_NOTES"
