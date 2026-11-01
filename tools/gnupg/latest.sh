#!/usr/bin/env bash
# Newest 2.5.x release in gnupg.org's download folder (2.4 is end of life; 2.5 is stable).
set -euo pipefail

curl -fsSL --retry 3 https://gnupg.org/ftp/gcrypt/gnupg/ \
    | grep -oE 'gnupg-2\.5\.[0-9]+\.tar\.bz2"' | sed -E 's/^gnupg-(.*)\.tar\.bz2"$/\1/' \
    | sort -uV | tail -1
