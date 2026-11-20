#!/usr/bin/env bash
# Newest GNU Make release in ftp.gnu.org's folder (make-X.Y.tar.gz or make-X.Y.Z.tar.gz).
set -euo pipefail

curl -fsSL --retry 3 https://ftp.gnu.org/gnu/make/ \
    | grep -oE 'make-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz"' | sed -E 's/^make-(.*)\.tar\.gz"$/\1/' \
    | sort -uV | tail -1
