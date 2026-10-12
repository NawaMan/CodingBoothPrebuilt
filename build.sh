#!/usr/bin/env bash
#
# Build one tool at one version for the current machine and package it.
#
# Usage: ./build.sh <tool> <version> [output-dir]
#
# Runs as root inside an ubuntu:<version> container (the workflow does this; locally:
#   docker run --rm -v "$PWD:/src" -w /src ubuntu:26.04 ./build.sh make 4.4.1
# ). The tool's own tools/<tool>/build.sh installs what it needs, builds, smoke-tests,
# and puts the files to ship into $PKG_DIR. This script then adds BUILD-INFO.txt and
# writes <asset>.tar.gz plus <asset>.tar.gz.sha256 into the output dir.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

TOOL="${1:?usage: $0 <tool> <version> [output-dir]}"
VERSION="${2:?usage: $0 <tool> <version> [output-dir]}"
OUT_DIR="$(mkdir -p "${3:-dist}" && cd "${3:-dist}" && pwd)"

TOOL_DIR="$ROOT/tools/$TOOL"
[[ -f "$TOOL_DIR/tool.conf" ]] || { echo "error: unknown tool '$TOOL' (no $TOOL_DIR/tool.conf)" >&2; exit 1; }
# shellcheck source=/dev/null
source "$TOOL_DIR/tool.conf"
: "${ARCH_MODE:?tool.conf must set ARCH_MODE}" "${UPSTREAM:?tool.conf must set UPSTREAM}"

[[ $EUID -eq 0 ]] || { echo "error: run as root (inside a container)" >&2; exit 1; }
cb_apt ca-certificates curl jq file xz-utils

ARCH="$(cb_arch)"
DISTRO="$(cb_distro)"
NAME="$(cb_asset_name "$TOOL" "$VERSION" "$ARCH_MODE" "$DISTRO" "$ARCH")"
OS_NAME="$(. /etc/os-release && echo "$PRETTY_NAME")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKG_DIR="$WORK/$NAME"
mkdir -p "$PKG_DIR"

export TOOL VERSION ARCH DISTRO WORK PKG_DIR ROOT
# BUILD_NOTES: extra BUILD-INFO lines a tool script may append (compiler, node, …).
export BUILD_NOTES="$WORK/build-notes.txt"
: > "$BUILD_NOTES"

echo "==> Building $TOOL $VERSION ($NAME)"
bash "$TOOL_DIR/build.sh"

[[ -n "$(ls -A "$PKG_DIR")" ]] || { echo "error: $TOOL_DIR/build.sh left \$PKG_DIR empty" >&2; exit 1; }

{
    echo "tool:         $TOOL $VERSION"
    echo "upstream:     $UPSTREAM"
    if [[ "$ARCH_MODE" == native ]]; then
        echo "architecture: $ARCH"
        echo "built on:     $OS_NAME"
    else
        echo "architecture: any (built on $ARCH, $OS_NAME)"
    fi
    cat "$BUILD_NOTES"
    echo "built at:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PKG_DIR/BUILD-INFO.txt"

echo "==> Packaging $NAME"
tar -czf "$OUT_DIR/$NAME.tar.gz" -C "$WORK" "$NAME"
(cd "$OUT_DIR" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
echo "==> Done: $OUT_DIR/$NAME.tar.gz"
