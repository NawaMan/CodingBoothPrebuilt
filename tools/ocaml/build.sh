#!/usr/bin/env bash
# Build the entire compiler/tool environment on CI, with one compile job from the start.
set -euo pipefail
source "$ROOT/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tool.conf"
[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-tools([0-9]+)$ ]] || {
    echo "error: expected <compiler>-tools<revision>, got '$VERSION'" >&2; exit 1;
}
compiler="${BASH_REMATCH[1]}"
[[ "${BASH_REMATCH[2]}" == "$TOOLS_REVISION" ]] || {
    echo "error: this builder supports tools$TOOLS_REVISION" >&2; exit 1;
}
prefix="${PREFIX_PATTERN//\{version\}/$VERSION}"
[[ ! -e "$prefix" ]] || { echo "error: build prefix already exists: $prefix" >&2; exit 1; }

cb_apt opam build-essential m4 pkg-config git rsync unzip bubblewrap libgmp-dev libev-dev
export OPAMROOT="$prefix/opam" OPAMSWITCH=booth OPAMJOBS=1 OPAMDOWNLOADJOBS=2
export OPAMROOTISOK=1 LANG=C.UTF-8 LC_ALL=C.UTF-8
mkdir -p "$prefix/bin"
# Ship the real package manager, not a wrapper that can recurse into itself.
cp /usr/bin/opam "$prefix/bin/opam"
opam init --bare --disable-sandboxing --no-setup --yes default https://opam.ocaml.org
opam switch create booth "ocaml-base-compiler.$compiler" --yes --jobs=1
opam install --yes --jobs=1 "dune.$DUNE_VERSION" "utop.$UTOP_VERSION" "ocamlformat.$OCAMLFORMAT_VERSION"

cat > "$prefix/env.sh" <<EOF
# This bundle must be extracted at $prefix.
export OPAMROOT='$prefix/opam'
export OPAMSWITCH=booth
export OCAML_HOME='$prefix/opam/booth'
export OCAML_TOPLEVEL_PATH="\$OCAML_HOME/lib/toplevel"
export CAML_LD_LIBRARY_PATH="\$OCAML_HOME/lib/stublibs:\$OCAML_HOME/lib/ocaml/stublibs"
export OPAMJOBS=\${OPAMJOBS:-1}
case ":\$PATH:" in
    *":\$OCAML_HOME/bin:"*) ;;
    *) export PATH="\$OCAML_HOME/bin:$prefix/bin:\$PATH" ;;
esac
EOF
printf '%s\n' "$VERSION" > "$prefix/BUNDLE-VERSION"
opam switch export --full "$prefix/SWITCH-STATE.export"
mkdir -p "$prefix/licenses"
cp /usr/share/doc/opam/copyright "$prefix/licenses/opam-copyright"
for package in "$OPAMROOT/booth/.opam-switch/sources/"*; do
    [[ -d "$package" ]] || continue
    for license in "$package"/LICENSE* "$package"/COPYING*; do
        [[ -f "$license" ]] || continue
        mkdir -p "$prefix/licenses/$(basename "$package")"
        cp "$license" "$prefix/licenses/$(basename "$package")/"
    done
done
cp "$ROOT/tools/ocaml/smoke.sh" "$prefix/smoke.sh"
opam clean --all --logs --yes
chmod -R a+rX "$prefix"
bash "$prefix/smoke.sh" "$prefix"
cp -a "$prefix/." "$PKG_DIR/"
{
    echo "compiler:     OCaml $compiler"
    echo "tools:        dune $DUNE_VERSION, utop $UTOP_VERSION, ocamlformat $OCAMLFORMAT_VERSION"
    echo "opam:         $(opam --version)"
    echo "prefix:       $prefix (extract here; absolute paths are embedded)"
    echo "build jobs:   1 (compiler and packages)"
    echo "runtime:      build-essential m4 pkg-config git rsync unzip libgmp10 libev4 libzstd1"
} >> "$BUILD_NOTES"
