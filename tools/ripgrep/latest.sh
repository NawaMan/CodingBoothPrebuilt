#!/usr/bin/env bash
# Newest stable ripgrep on crates.io (what an unpinned `cargo install ripgrep` gets).
set -euo pipefail
source "$ROOT/lib/common.sh"
cb_crate_latest ripgrep
