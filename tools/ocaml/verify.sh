#!/usr/bin/env bash
# Runs in a NEW Ubuntu container, without the build environment or its apt dependencies.
set -euo pipefail
archive="${1:?usage: verify.sh <archive>}"
name=$(basename "$archive" .tar.gz)
[[ "$name" =~ ^ocaml-([0-9]+\.[0-9]+\.[0-9]+-tools[0-9]+)-ubuntu[0-9.]+-(x86_64|arm64)$ ]] || exit 1
prefix="/opt/ocaml/ocaml-${BASH_REMATCH[1]}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential m4 pkg-config git rsync unzip \
    ca-certificates curl libgmp10 libev4 libzstd1 > /dev/null
(cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive").sha256")
mkdir -p "$prefix"
tar -xzf "$archive" -C "$prefix" --strip-components=1 --no-same-owner
useradd --create-home --shell /bin/bash ocaml-test
chown -R ocaml-test:ocaml-test "$prefix/opam"
runuser -u ocaml-test -- bash "$prefix/smoke.sh" "$prefix"
# A new package proves that the extracted opam state is writable and usable by the user.
runuser -u ocaml-test -- bash -s -- "$prefix" <<'EOF'
set -euo pipefail
source "$1/env.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
printf 'let () = print_endline "Installed as user"\n' > proof.ml
cat > codingbooth-proof.opam <<'OPAM'
opam-version: "2.0"
name: "codingbooth-proof"
version: "0.1"
synopsis: "Verify an extracted CodingBooth opam environment"
maintainer: "CodingBooth"
depends: ["ocaml"]
build: [["ocamlc" "-o" "proof" "proof.ml"]]
install: [["cp" "proof" bin]]
OPAM
opam pin add codingbooth-proof "$work" --yes
test "$(proof)" = 'Installed as user'
EOF
echo 'Fresh-container verification passed as a non-root user.'
