#!/usr/bin/env bash
# Runs in a NEW Ubuntu container: sets up a ghcup tree the way CodingBooth's haskell setup
# does (/opt/haskell/haskell-<ghc>, GHC from this repo's ghc release when published, else
# ghcup), unpacks the archive into its .ghcup/hls/<hls> as the lsp--hls setup will, and
# type-checks as a non-root user. Catches a server that needs anything of the build's.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="${1:?usage: verify.sh <archive>}"
name=$(basename "$archive" .tar.gz)
[[ "$name" =~ ^hls-([0-9.]+)-ghc([0-9.]+)-(ubuntu[0-9.]+)-(x86_64|arm64)$ ]] || {
    echo "error: expected hls-<hls>-ghc<ghc>-ubuntu<ver>-<arch>.tar.gz, got '$(basename "$archive")'" >&2; exit 1;
}
hls="${BASH_REMATCH[1]}" ghc="${BASH_REMATCH[2]}" distro="${BASH_REMATCH[3]}" arch="${BASH_REMATCH[4]}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils gzip git make \
    build-essential libgmp-dev zlib1g-dev libtinfo6 libffi-dev libncurses-dev > /dev/null
(cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive").sha256")

base="/opt/haskell/haskell-$ghc"
export GHCUP_INSTALL_BASE_PREFIX="$base" GHCUP_SKIP_UPDATE_CHECK=1 \
       BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1
mkdir -p "$base"
curl -fsSL --retry 3 https://get-ghcup.haskell.org | bash > /tmp/ghcup.log 2>&1 || { tail -40 /tmp/ghcup.log; exit 1; }
ghcup="$base/.ghcup/bin/ghcup"
dest="$base/.ghcup/ghc/$ghc"
url="https://github.com/NawaMan/CodingBoothPrebuilt/releases/download/ghc-$ghc/ghc-$ghc-$distro-$arch.tar.gz"
if curl -fsSL --retry 3 "$url" -o /tmp/ghc.tar.gz; then
    echo "==> GHC $ghc from $url"
    mkdir -p "$dest" && tar -xzf /tmp/ghc.tar.gz -C "$dest" --strip-components=1 --no-same-owner
    grep -lr "/opt/ghc/ghc-$ghc" "$dest/bin" | xargs -r sed -i "s|/opt/ghc/ghc-$ghc|$dest|g"
    rm -f /tmp/ghc.tar.gz "$dest/BUILD-INFO.txt"
else
    echo "==> GHC $ghc with ghcup (no prebuilt published)"
    "$ghcup" install ghc "$ghc" > /tmp/ghcup.log 2>&1 || { tail -40 /tmp/ghcup.log; exit 1; }
fi
{ "$ghcup" set ghc "$ghc" && "$ghcup" install cabal recommended && "$ghcup" set cabal recommended; } \
    > /tmp/ghcup.log 2>&1 || { tail -40 /tmp/ghcup.log; exit 1; }

mkdir -p "$base/.ghcup/hls/$hls"
tar -xzf "$archive" -C "$base/.ghcup/hls/$hls" --strip-components=1 --no-same-owner
bash "$here/ghcup-link.sh" "$base/.ghcup" "$hls" "$ghc"
"$ghcup" list -t hls -c set -r | grep -qE "^hls $hls( |\$)" \
    || { "$ghcup" list -t hls; echo "error: ghcup does not list HLS $hls as set" >&2; exit 1; }

useradd --create-home --shell /bin/bash hls-test
install -m 755 "$here/smoke.sh" /tmp/hls-smoke.sh
runuser -u hls-test -- env PATH="$base/.ghcup/bin:$PATH" CABAL_DIR=/home/hls-test/.cabal \
    bash -c 'cabal update > /dev/null && bash /tmp/hls-smoke.sh "$0" "$1"' "$hls" "$ghc"
echo 'Fresh-container verification passed as a non-root user.'
