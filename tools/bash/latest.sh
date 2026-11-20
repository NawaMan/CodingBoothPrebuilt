#!/usr/bin/env bash
# Newest GNU Bash release tarball in ftp.gnu.org's folder (bash-X.Y.tar.gz or
# bash-X.Y.Z.tar.gz).
set -euo pipefail

curl -fsSL --retry 3 https://ftp.gnu.org/gnu/bash/ \
    | grep -oE 'bash-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.gz"' | sed -E 's/^bash-(.*)\.tar\.gz"$/\1/' \
    | sort -uV | tail -1
