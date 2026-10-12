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
| `make` | GNU Make (GPG-verified source) | per Ubuntu + arch | `bin/make` …, built with prefix `/opt/make/make-<ver>` |
| `evcxr_jupyter` | Rust Jupyter kernel (upstream ships no linux arm64) | per Ubuntu + arch | `bin/evcxr_jupyter` |
| `scratch-gui` | Scratch 3 editor, static web files (upstream archived at 5.3.0; AGPL-3.0) | once, any arch | contents of `build/`, plus `LICENSE` and `SOURCE.txt` |
| `excalidraw` | Excalidraw self-hosted app, static web files | once, any arch | contents of `excalidraw-app/build/` |

Every tarball unpacks to a single folder named after the asset, holding the files above plus
`BUILD-INFO.txt` (source, compiler or Node version, build time). Each `.tar.gz` has a matching
`.sha256`.

## Releases and asset names

One release per tool version, tagged `<tool>-<version>`, e.g. `make-4.4.1`.

| Kind | Asset |
|---|---|
| per Ubuntu + arch | `<tool>-<version>-ubuntu<ver>-<x86_64\|arm64>.tar.gz` |
| any arch | `<tool>-<version>.tar.gz` |

## Using

```sh
base=https://github.com/NawaMan/CodingBoothPrebuilt/releases/download/make-4.4.1
asset=make-4.4.1-ubuntu26.04-x86_64.tar.gz
curl -fsSLO "$base/$asset" -O "$base/$asset.sha256"
sha256sum -c "$asset.sha256"
mkdir -p /opt/make/make-4.4.1
tar -xzf "$asset" -C /opt/make/make-4.4.1 --strip-components=1
```

A setup should fall back to building from source when the asset for its version, Ubuntu or
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
docker run --rm -v "$PWD:/src" -w /src ubuntu:26.04 ./build.sh make 4.4.1 dist   # root-owned output in ./dist
./latest.sh make            # on the host; needs curl and jq
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

## Notes

- arm64 builds use GitHub's `ubuntu-*-arm` hosted runners, which are free for public repositories only.
- `scratch-gui` is AGPL-3.0-only. Its bundle ships the license and `SOURCE.txt`, which names the
  exact upstream tag and commit it was built from.
