# shellcheck shell=bash
# Shared helpers for build.sh, latest.sh and the tool scripts under tools/.
# Sourced, never executed.

# Architecture label used in asset names: x86_64 or arm64.
cb_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo x86_64 ;;
        aarch64|arm64) echo arm64  ;;
        *) echo "error: unsupported architecture $(uname -m)" >&2; return 1 ;;
    esac
}

# Distro label used in asset names, e.g. ubuntu26.04. Read in a subshell:
# os-release defines VERSION, which would clobber the caller's.
cb_distro() {
    (. /etc/os-release && echo "${ID}${VERSION_ID}")
}

# Asset (and top-level folder) name for one build.
#   cb_asset_name <tool> <version> <arch-mode> [distro] [arch]
# arch-mode "native" → <tool>-<version>-<distro>-<arch>   (one build per Ubuntu + CPU)
# arch-mode "any"    → <tool>-<version>                  (static web files etc.)
cb_asset_name() {
    local tool="$1" version="$2" mode="$3" distro="${4:-}" arch="${5:-}"
    case "$mode" in
        native) echo "$tool-$version-$distro-$arch" ;;
        any)    echo "$tool-$version" ;;
        *) echo "error: unknown ARCH_MODE '$mode'" >&2; return 1 ;;
    esac
}

# Release tag holding every asset of one tool version.
cb_tag() { echo "$1-$2"; }

# curl with retries. --connect-timeout keeps one dead host from eating minutes.
cb_fetch() {
    curl -fsSL --connect-timeout 20 --retry 5 --retry-delay 3 --retry-all-errors -o "$2" "$1"
}

# Fetch a path from the first GNU mirror that answers.
#   cb_fetch_gnu <path-under-/gnu/> <dest>
cb_fetch_gnu() {
    local path="$1" dest="$2" mirror
    for mirror in https://ftpmirror.gnu.org https://mirrors.kernel.org/gnu https://ftp.gnu.org/gnu; do
        cb_fetch "$mirror/$path" "$dest" && return 0
        echo "   $mirror failed, trying the next mirror..." >&2
    done
    echo "error: could not download $path from any GNU mirror" >&2
    return 1
}

# Latest release tag of a GitHub repo, with any leading "v" dropped.
# Uses GITHUB_TOKEN / GH_TOKEN when set (the Actions runner has one) to avoid the
# 60-requests-per-hour anonymous limit.
cb_github_latest_release() {
    local repo="$1" token="${GITHUB_TOKEN:-${GH_TOKEN:-}}" auth=()
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
    curl -fsSL --retry 3 "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" \
        | jq -er '.tag_name' | sed 's/^v//'
}

# Tag names of a GitHub repo's published releases (no drafts or prereleases), newest
# first, without a leading "v". Covers the newest 100.
cb_github_releases() {
    local repo="$1" token="${GITHUB_TOKEN:-${GH_TOKEN:-}}" auth=()
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
    curl -fsSL --retry 3 "${auth[@]}" "https://api.github.com/repos/$repo/releases?per_page=100" \
        | jq -er '.[] | select(.draft or .prerelease | not) | .tag_name' | sed 's/^v//'
}

# Newest release of a Go module, from the Go module proxy, without the leading "v".
#   cb_go_module_latest <module path>     e.g. golang.org/x/tools
cb_go_module_latest() {
    curl -fsSL --retry 3 "https://proxy.golang.org/$1/@latest" | jq -er '.Version' | sed 's/^v//'
}

# Install the newest Go from go.dev into $WORK/go and put it on PATH, with GOPATH and the
# build cache under $WORK and cgo off (static binaries). A module whose go.mod names a newer
# toolchain still fetches that one. Exports GOPATH.
cb_install_go() {
    local go_arch go_version
    case "$ARCH" in x86_64) go_arch=amd64 ;; arm64) go_arch=arm64 ;; esac
    go_version=$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | jq -er '.[0].version')
    echo "==> Installing $go_version"
    cb_fetch "https://go.dev/dl/$go_version.linux-$go_arch.tar.gz" "$WORK/go.tar.gz"
    tar -xzf "$WORK/go.tar.gz" -C "$WORK"
    export PATH="$WORK/go/bin:$WORK/gopath/bin:$PATH" GOPATH="$WORK/gopath" GOCACHE="$WORK/gocache" CGO_ENABLED=0
}

# Build one Go command at $VERSION of its module with `go install` and check it is that
# version and static. Needs cb_install_go first. Smoke tests are the caller's: run them on
# $CB_GO_BIN, then cb_go_package.
#   cb_go_build <module> <package>   e.g. github.com/go-delve/delve github.com/go-delve/delve/cmd/dlv
cb_go_build() {
    CB_GO_MODULE="$1" CB_GO_PACKAGE="$2"
    echo "==> go install $CB_GO_PACKAGE@v$VERSION"
    GOBIN="$WORK/bin" go install "$CB_GO_PACKAGE@v$VERSION" > "$WORK/build.log" 2>&1 \
        || { tail -80 "$WORK/build.log"; return 1; }
    CB_GO_BIN="$WORK/bin/${CB_GO_PACKAGE##*/}"
    local built
    built=$(go version -m "$CB_GO_BIN" | awk '$1 == "mod" { print $3 }')
    [[ "$built" == "v$VERSION" ]] \
        || { echo "error: $CB_GO_BIN reports module version '$built', not v$VERSION" >&2; return 1; }
    file "$CB_GO_BIN" | grep -q "statically linked" \
        || { echo "error: $CB_GO_BIN is not static: $(file "$CB_GO_BIN")" >&2; return 1; }
    echo "==> Testing"
}

# Package what cb_go_build built: bin/<command> plus the module's LICENSE. A module in a
# repo subfolder may not carry the repo-root LICENSE in its zip; <license-url> is fetched
# then.
#   cb_go_package [license-url]
cb_go_package() {
    local license_url="${1:-}" mod_license
    echo "smoke tests passed"
    mkdir -p "$PKG_DIR/bin"
    cp "$CB_GO_BIN" "$PKG_DIR/bin/"
    mod_license="$(go env GOMODCACHE)/$CB_GO_MODULE@v$VERSION/LICENSE"
    if [[ -f "$mod_license" ]]; then cp "$mod_license" "$PKG_DIR/LICENSE"
    elif [[ -n "$license_url" ]]; then cb_fetch "$license_url" "$PKG_DIR/LICENSE"
    else echo "error: no LICENSE in $CB_GO_MODULE@v$VERSION and no URL given" >&2; return 1; fi
    {
        echo "source:       $CB_GO_PACKAGE@v$VERSION (go install, CGO_ENABLED=0)"
        echo "compiler:     $(go version -m "$CB_GO_BIN" | head -1 | awk '{print $2}')"
    } >> "$BUILD_NOTES"
}

# Install a minimal stable Rust into $WORK and build crate <crate> at $VERSION with
# `cargo install --locked`. Every executable it installs is checked for unresolved
# libraries. Smoke tests are the caller's: run them on $CB_CARGO_ROOT/bin/*, then
# cb_cargo_package.
#   cb_cargo_build <crate>
cb_cargo_build() {
    CB_CARGO_CRATE="$1"
    cb_apt build-essential pkg-config
    echo "==> Installing a Rust toolchain (stable, minimal)"
    export RUSTUP_HOME="$WORK/rustup" CARGO_HOME="$WORK/cargo"
    cb_fetch https://sh.rustup.rs "$WORK/rustup-init.sh"
    sh "$WORK/rustup-init.sh" -y -q --profile minimal --no-modify-path >/dev/null
    export PATH="$CARGO_HOME/bin:$PATH"
    rustc --version
    echo "==> cargo install --locked $CB_CARGO_CRATE $VERSION"
    CB_CARGO_ROOT="$WORK/root"
    cargo install --locked --quiet "$CB_CARGO_CRATE" --version "=$VERSION" --root "$CB_CARGO_ROOT" \
        > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; return 1; }
    local bin missing
    for bin in "$CB_CARGO_ROOT"/bin/*; do
        missing="$(ldd "$bin" | grep 'not found' || true)"
        [[ -z "$missing" ]] || { echo "error: $bin is missing shared libraries: $missing" >&2; return 1; }
    done
    echo "==> Testing"
}

# Package what cb_cargo_build built: the named executables, stripped, plus the crate's
# licence files.
#   cb_cargo_package <executable>...
cb_cargo_package() {
    local bin src f
    echo "smoke tests passed"
    mkdir -p "$PKG_DIR/bin"
    for bin in "$@"; do
        cp "$CB_CARGO_ROOT/bin/$bin" "$PKG_DIR/bin/"
        strip "$PKG_DIR/bin/$bin"
    done
    src="$(find "$CARGO_HOME/registry/src" -maxdepth 2 -type d -name "$CB_CARGO_CRATE-$VERSION" | head -1)"
    for f in LICENSE LICENSE-MIT LICENSE-APACHE UNLICENSE COPYING COPYRIGHT; do
        if [[ -f "$src/$f" ]]; then cp "$src/$f" "$PKG_DIR/"; fi
    done
    {
        echo "source:       crates.io $CB_CARGO_CRATE $VERSION (cargo install --locked)"
        echo "compiler:     $(rustc --version)"
    } >> "$BUILD_NOTES"
}

# Newest stable version of a crate on crates.io (its API requires a User-Agent).
cb_crate_latest() {
    curl -fsSL --retry 3 -A "CodingBoothPrebuilt (https://github.com/NawaMan/CodingBoothPrebuilt)" \
        "https://crates.io/api/v1/crates/$1" | jq -er '.crate.max_stable_version'
}

# True when version $1 sorts before $2 (sort -V order: 9.12.4 < 9.13).
cb_version_lt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

# From X.Y.Z versions on stdin, the newest of each X.Y series at or above <from>, plus any
# extra series named, oldest first. Other shapes (prereleases, betas) are dropped.
#   cb_newest_per_series <from> [<series>...]
cb_newest_per_series() {
    local from="$1"; shift
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | awk -F. -v from="$from" -v also=" $* " '
        BEGIN { split(from, f, ".") }
        { series = $1 "." $2 }
        $1 > f[1] || ($1 == f[1] && $2 >= f[2]) || index(also, " " series " ") { newest[series] = $0 }
        END { for (s in newest) print newest[s] }' | sort -V
}

# "<version> <ghc>" for <package> in each Stackage LTS major from <from-lts> up to the
# current one, newest first, then nightly: the versions Stack users get, each with the
# GHC its snapshot builds it with. Snapshots without the package print nothing.
#   cb_stackage_versions <package> <from-lts>
cb_stackage_versions() {
    local pkg="$1" from="$2" newest n snapshot ghc version snapshots=()
    newest=$(curl -fsSL --retry 3 -H 'Accept: application/json' https://www.stackage.org/lts \
               | jq -er '.snapshot.name' | sed -nE 's/^lts-([0-9]+)\..*/\1/p') || return 1
    [[ -n "$newest" ]] || { echo "error: could not read the current Stackage LTS" >&2; return 1; }
    for (( n = newest; n >= from; n-- )); do snapshots+=("lts-$n"); done
    snapshots+=(nightly)
    for snapshot in "${snapshots[@]}"; do
        ghc=$(curl -fsSL --retry 3 -H 'Accept: application/json' "https://www.stackage.org/$snapshot" \
                | jq -er '.snapshot.ghc') || return 1
        version=$(curl -fsSL --retry 3 "https://www.stackage.org/$snapshot/cabal.config" \
                    | sed -nE "s/^(constraints:)?[[:space:]]*$pkg ==([0-9.]+),?\$/\\2/p") || return 1
        [[ -n "$version" ]] && echo "$version $ghc"
    done
    return 0
}

# apt-get install, quietly, only the packages not installed yet.
cb_apt() {
    local missing=() p
    for p in "$@"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    (( ${#missing[@]} == 0 )) && return 0
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
}

# Install the newest Node.js of a major line from nodejs.org into /opt/node and
# put it on PATH. Official tarballs exist for x64 and arm64.
cb_install_node() {
    local major="$1" node_arch version
    case "$(cb_arch)" in x86_64) node_arch=x64 ;; arm64) node_arch=arm64 ;; esac
    version=$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json \
        | jq -er --arg m "v$major." 'map(select(.version | startswith($m)))[0].version')
    echo "==> Installing Node.js $version"
    cb_fetch "https://nodejs.org/dist/$version/node-$version-linux-$node_arch.tar.xz" /tmp/node.tar.xz
    rm -rf /opt/node && mkdir -p /opt/node
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1
    rm -f /tmp/node.tar.xz
    export PATH="/opt/node/bin:$PATH"
}

# GHC 9.4's bindists hardcode gold into the hsc2hs wrapper (HSC2HS_EXTRA), and Ubuntu
# 26.04 ships no gold, so every package that runs hsc2hs fails to link. GHC itself links
# with the default ld; make the wrapper do the same.
#   cb_ghc_drop_gold <ghc-dir>
cb_ghc_drop_gold() {
    local f
    for f in "$1"/bin/hsc2hs*; do
        if [[ -f "$f" && ! -L "$f" ]] && grep -q -- '-fuse-ld=gold' "$f"; then
            sed -i 's/ *--lflag=-fuse-ld=gold//' "$f"
        fi
    done
}

# The GHC to build Hackage package <package> at $VERSION with: that of the newest Stackage
# snapshot (LTS <from-lts> on, then nightly) shipping it, else ghcup's recommended one.
# Each hlint/ormolu release pins one ghc-lib-parser series whose base bounds exclude
# other GHCs; the snapshot's GHC is one its bounds allow.
#   cb_build_ghc <package> <from-lts>
cb_build_ghc() {
    local ghc
    ghc=$(cb_stackage_versions "$1" "$2" | awk -v v="$VERSION" '$1 == v && !found++ { print $2 }') || return 1
    echo "${ghc:-recommended}"
}

# Install GHC (and the recommended cabal) with ghcup into $WORK/ghcup and put them on
# PATH -- the same way CodingBooth's haskell setup installs them.
#   cb_install_ghc <ghc-version|recommended>
cb_install_ghc() {
    local ghc="$1" log="$WORK/ghcup.log"
    cb_apt build-essential gzip libgmp-dev zlib1g-dev libtinfo6 libffi-dev libncurses-dev
    echo "==> Installing GHC $ghc and cabal with ghcup"
    export GHCUP_INSTALL_BASE_PREFIX="$WORK/ghcup" GHCUP_SKIP_UPDATE_CHECK=1 \
           BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1
    cb_fetch https://get-ghcup.haskell.org "$WORK/get-ghcup.sh"
    local ghcup="$WORK/ghcup/.ghcup/bin/ghcup"
    {
        bash "$WORK/get-ghcup.sh" &&
        "$ghcup" install ghc "$ghc" && "$ghcup" set ghc "$ghc" &&
        "$ghcup" install cabal recommended && "$ghcup" set cabal recommended
    } > "$log" 2>&1 || { tail -40 "$log"; return 1; }
    local dir
    for dir in "$WORK"/ghcup/.ghcup/ghc/*; do cb_ghc_drop_gold "$dir"; done
    export PATH="$WORK/ghcup/.ghcup/bin:$PATH" CABAL_DIR="$WORK/cabal"
    cabal update > /dev/null
}
