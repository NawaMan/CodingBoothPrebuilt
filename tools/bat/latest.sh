#!/usr/bin/env bash
# Newest stable bat on crates.io (what an unpinned `cargo install bat` gets).
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_crate_latest bat
