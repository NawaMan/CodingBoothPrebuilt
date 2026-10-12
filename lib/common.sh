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
