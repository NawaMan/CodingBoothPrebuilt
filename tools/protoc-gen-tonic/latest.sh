#!/usr/bin/env bash
# Newest stable protoc-gen-tonic on crates.io (its API requires a User-Agent).
set -euo pipefail

curl -fsSL --retry 3 -A "CodingBoothPrebuilt (https://github.com/NawaMan/CodingBoothPrebuilt)" \
    https://crates.io/api/v1/crates/protoc-gen-tonic | jq -er '.crate.max_stable_version'
