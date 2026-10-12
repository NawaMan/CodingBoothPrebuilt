#!/usr/bin/env bash
# Newest stable evcxr_jupyter on crates.io (its API requires a User-Agent).
set -euo pipefail

curl -fsSL --retry 3 -A "CodingBoothPrebuilt (https://github.com/NawaMan/CodingBoothPrebuilt)" \
    https://crates.io/api/v1/crates/evcxr_jupyter | jq -er '.crate.max_stable_version'
