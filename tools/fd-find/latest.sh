#!/usr/bin/env bash
# Newest stable fd-find on crates.io (what an unpinned `cargo install fd-find` gets).
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_crate_latest fd-find
