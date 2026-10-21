# CodingBoothPrebuilt

Prebuilt binaries and web bundles for [CodingBooth](https://github.com/NawaMan/CodingBooth) setups
that would otherwise compile from source while a booth image builds. Each one is built in
GitHub Actions, natively on x86_64 and arm64 runners, inside the Ubuntu version CodingBooth's
base image uses, then smoke-tested and published as a GitHub Release asset.

Bash 3.2 lives in its own repo, [Bash32Ubuntu](https://github.com/NawaMan/Bash32Ubuntu), because
it is useful outside CodingBooth too.

## Tools

| Tool | What it is | Builds | Asset layout |
|---|---|---|---|
| `ocaml` | OCaml compiler, Dune, UTop and OCamlFormat; version is `<compiler>-tools<revision>` | per Ubuntu + arch | complete opam environment; extract to `/opt/ocaml/ocaml-<version>` |
| `evcxr_jupyter` | Rust Jupyter kernel (upstream ships no linux arm64) | per Ubuntu + arch | `bin/evcxr_jupyter` |
| `ghc` | GHC as ghcup installs it (whose own install step takes 6-7 minutes in a Docker build) | per Ubuntu + arch | ghcup's `.ghcup/ghc/<version>/` (`bin/`, `lib/`, `share/`), built at `/opt/ghc/ghc-<version>` |
| `ihaskell` | Haskell Jupyter kernel, for one exact GHC; version is `<ihaskell>-ghc<ghc>` | per Ubuntu + arch | `bin/ihaskell` plus its data files under `store/`; extract to `/opt/ihaskell/ihaskell-<version>` |
| `hlint` | Haskell linter; upstream ships x86_64 only | arm64 only | `hlint` plus `data/`, like upstream's release |
| `ormolu` | Haskell formatter; upstream ships x86_64 only | arm64 only | `ormolu` |
| `scratch-gui` | Scratch 3 editor, static web files (upstream archived at 5.3.0; AGPL-3.0) | once, any arch | contents of `build/`, plus `LICENSE` and `SOURCE.txt` |
| `excalidraw` | Excalidraw self-hosted app, static web files | once, any arch | contents of `excalidraw-app/build/` |

Every tarball unpacks to a single folder named after the asset, holding the files above plus
`BUILD-INFO.txt` (source, compiler or Node version, build time). Each `.tar.gz` has a matching
`.sha256`.

## Releases and asset names

One release per tool version, tagged `<tool>-<version>`, e.g. `evcxr_jupyter-0.22.0`.

| Kind | Asset |
|---|---|
| per Ubuntu + arch | `<tool>-<version>-ubuntu<ver>-<x86_64\|arm64>.tar.gz` |
| any arch | `<tool>-<version>.tar.gz` |

## Using

```sh
base=https://github.com/NawaMan/CodingBoothPrebuilt/releases/download/evcxr_jupyter-0.22.0
asset=evcxr_jupyter-0.22.0-ubuntu26.04-x86_64.tar.gz
curl -fsSLO "$base/$asset" -O "$base/$asset.sha256"
sha256sum -c "$asset.sha256"
mkdir -p /opt/evcxr
tar -xzf "$asset" -C /opt/evcxr --strip-components=1
```

`ihaskell` is the exception to "extract anywhere": its data files are found through paths
fixed at build time, so it must land in `/opt/ihaskell/ihaskell-<version>`. It needs the GHC
named in its version (installed by ghcup) and is registered with
`ihaskell install --ghclib "$(ghc --print-libdir)"`.

`ghc` unpacks anywhere, with one fix-up: the wrapper scripts in `bin/` name the build prefix,
so rewrite `/opt/ghc/ghc-<version>` in them to the new folder. Unpacked into a ghcup tree's
`.ghcup/ghc/<version>`, ghcup lists it as installed and `ghcup set ghc <version>` works.

`ocaml` bundles a compiler and a pinned tool set, e.g. `5.5.1-tools1` (`tools1`: Dune 3.24.0,
UTop 2.17.0, OCamlFormat 0.29.0). `tools/ocaml/tool.conf` owns the tool pins; changing
these pins requires a new `toolsN` revision, so published bundles keep their identity.
The weekly run pairs the newest OCaml release with the current pins. If a new compiler is
outside a pinned tool's bounds, that build fails until the pins and `toolsN` are bumped.
The full opam root, compiler libraries, package state, licenses and `SWITCH-STATE.export`
are included. Source `env.sh` at its fixed prefix; the export file records the build
and is not a substitute for the binary archive.

The build uses one compile job from compiler creation onward. CI then extracts the
archive in a fresh Ubuntu container and, as a non-root user, compiles bytecode and native
programs, builds with Dune, runs UTop, formats with OCamlFormat, and installs a local opam
package. A failed verification prevents that archive from being published. CodingBooth's
OCaml setup requires a published archive: it never starts a source build automatically.
To build a version on CI, dispatch `tools=ocaml`, `versions=5.5.1-tools1`,
`architectures=both`, `ubuntu=26.04`. Additional project packages may still compile locally.

For the other tools, a setup should fall back to building from source when the asset for its version, Ubuntu or
architecture is not published (a 404).

## Building

Everything is built by GitHub Actions: **Actions → Build prebuilt tools → Run workflow**.

| Input | Default | Meaning |
|---|---|---|
| `tools` | `all` | Folder names under `tools/`, space or comma separated |
| `versions` | `latest` | Versions to build; explicit versions need a single tool |
| `architectures` | `both` | `both`, `x86_64` or `arm64` (arch-independent tools always build once) |
| `ubuntu` | `codingbooth` | `codingbooth` reads `UBUNTU_VERSION` from CodingBooth's base Dockerfile; or `26.04` / `24.04` / `22.04` |
| `publish` | `true` | Upload to the release `<tool>-<version>` |
| `force` | `false` | Rebuild and overwrite assets that are already published |

The workflow is idempotent: a combination whose asset is already in the release is skipped,
and the run summary lists what was built and what was skipped. When one build fails, the ones
that succeeded are still published and the run is marked failed.

**New upstream versions.** A scheduled run every Monday builds the latest upstream version of
every tool (`tools/<tool>/latest.sh`), so a new release is prebuilt within a week and nothing
else is rebuilt. If a version lookup fails, the run is marked failed. Dependabot keeps the
workflow's GitHub Actions current. Bumping the version CodingBooth pins is still a separate,
deliberate change in CodingBooth.

### Locally

`build.sh` expects to run as root in a throwaway Ubuntu container:

```sh
docker run --rm -v "$PWD:/src" -w /src ubuntu:26.04 ./build.sh evcxr_jupyter 0.22.0 dist   # root-owned output in ./dist
./latest.sh evcxr_jupyter   # on the host; needs curl and jq
```

## Adding a tool

Create `tools/<tool>/` with three files:

- **`tool.conf`**: sets `ARCH_MODE` (`native` for one build per Ubuntu + arch, `any` for one
  build that runs anywhere) and `UPSTREAM` (a URL), plus any settings of the tool's own.
- **`build.sh`**: runs as root in the container with `ROOT`, `TOOL`, `VERSION`, `ARCH`, `DISTRO`,
  `WORK`, `PKG_DIR` and `BUILD_NOTES` set. It installs what it needs (`cb_apt`, `cb_install_node`
  from `lib/common.sh`), builds, **smoke-tests**, and copies the files to ship into `$PKG_DIR`.
  Lines appended to `$BUILD_NOTES` end up in `BUILD-INFO.txt`. Ship the upstream license.
- **`latest.sh`**: prints the newest upstream version. It runs on the host.

A native tool that upstream already ships for some CPUs can set `ARCHES="arm64"` in
`tool.conf` to build only the missing ones.

## Notes

- arm64 builds use GitHub's `ubuntu-*-arm` hosted runners, which are free for public repositories only.
- `scratch-gui` is AGPL-3.0-only. Its bundle ships the license and `SOURCE.txt`, which names the
  exact upstream tag and commit it was built from.

An optional **`verify.sh <archive>`** runs in a fresh Ubuntu container after packaging.
It installs runtime prerequisites, verifies the checksum and extracted environment, and
exits nonzero on failure. Only archives with a successful verification marker are published
for tools that provide this hook.
