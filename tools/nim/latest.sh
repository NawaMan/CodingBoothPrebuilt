#!/usr/bin/env bash
# Newest stable Nim: nim-lang.org/channels/stable, the pointer choosenim (and CodingBooth's
# nim setup) reads. Nim doesn't publish GitHub Releases.
set -euo pipefail

curl -fsSL --retry 3 https://nim-lang.org/channels/stable | tr -d '[:space:]' | sed 's/^v//'
