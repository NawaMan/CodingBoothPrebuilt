#!/usr/bin/env bash
# GnuPG from the upstream release tarball, checked against its signature by a GnuPG release
# key, configured as CodingBooth's gnupg setup configures it. Called by ../../build.sh.
set -euo pipefail
source "$ROOT/lib/common.sh"

# Release signing keys, from https://gnupg.org/signature_key.html. Fixed here rather than
# trusted from the download server, which also serves the tarball. Keep in step with
# CodingBooth's variants/base/setups/gnupg--setup.sh.
RELEASE_KEYS=(
    6DAA6E64A76D2840571B4902528897B826403ADA   # Werner Koch (dist signing 2020)
    AC8E115BF73E2D8D47FA9908E98E9B2D19C6C8BD   # NIIBE Yutaka (GnuPG Release Key)
)

# Upstream fixes a release lacks, "<commit> <sha256 of its .patch>" each, as Homebrew's formula
# applies them. Keep in step with CodingBooth's variants/base/setups/gnupg--setup.sh.
PATCHES=()
case "$VERSION" in
    2.5.24)
        # https://dev.gnupg.org/T8469: a secret key imported without a passphrase cannot
        # decrypt (Homebrew 2.5.24_1).
        PATCHES=(
            "42386bcf8861f04c1bdec5cbb139a03da83d8ef9 93817449be3f93dcade3d79960e33e72959f54f95ff6108f22176bef28111f2b"
            "5523cec6913bcbd1a374d183899a6f298d2c0e32 0a0acd2f7f25723f3f84ec5c4ecf03b786d73ca61c48487d4d00c0559be89d66"
        ) ;;
esac

cb_apt bzip2 gcc make patch pkgconf gnupg \
    libgpg-error-dev libgcrypt20-dev libassuan-dev libksba-dev libnpth0-dev \
    libgnutls28-dev libsqlite3-dev libbz2-dev zlib1g-dev libreadline-dev libldap-dev

base=https://gnupg.org/ftp/gcrypt/gnupg
tarball="gnupg-$VERSION.tar.bz2"
echo "==> Downloading $tarball"
cb_fetch "$base/$tarball" "$WORK/$tarball"
cb_fetch "$base/$tarball.sig" "$WORK/$tarball.sig"

# Verified with Ubuntu's gpg in a throwaway home. The key file comes from the server too,
# so a signature only counts when its primary key is one of RELEASE_KEYS.
echo "==> Checking the release signature"
cb_fetch https://gnupg.org/signature_key.asc "$WORK/keys.asc"
mkdir -m 700 "$WORK/verifyhome"
gpg --batch --quiet --homedir "$WORK/verifyhome" --import "$WORK/keys.asc" 2>/dev/null || true
status=$(gpg --batch --homedir "$WORK/verifyhome" --status-fd 1 \
           --verify "$WORK/$tarball.sig" "$WORK/$tarball" 2>/dev/null || true)
trusted=""
for fpr in $(awk '$2 == "VALIDSIG" { print $NF }' <<< "$status"); do
    for key in "${RELEASE_KEYS[@]}"; do
        [[ "$fpr" == "$key" ]] && trusted="$fpr"
    done
done
[[ -n "$trusted" ]] || { echo "error: $tarball has no valid signature from a GnuPG release key" >&2; exit 1; }
echo "   good signature by $trusted"

echo "==> Building"
tar -xjf "$WORK/$tarball" -C "$WORK"
SRC="$WORK/gnupg-$VERSION"
STAGE="$WORK/stage"
applied=""
for entry in "${PATCHES[@]}"; do
    read -r commit sha256 <<< "$entry"
    # Kept in patches/: GitHub makes a commit's .patch on request and answers 503 far more
    # often than not, for minutes at a time. One that is not there is asked for, for up to
    # five minutes. Either way it has to match the SHA-256 above.
    if [[ -r "$ROOT/tools/gnupg/patches/$commit.patch" ]]; then
        cp "$ROOT/tools/gnupg/patches/$commit.patch" "$WORK/$commit.patch"
    else
        got=0
        for try in $(seq 1 60); do
            curl -fsSL --connect-timeout 20 -o "$WORK/$commit.patch" \
                "https://github.com/gpg/gnupg/commit/$commit.patch?full_index=1" 2>/dev/null && { got=1; break; }
            sleep 5
        done
        (( got )) || { echo "error: GitHub did not serve $commit.patch in five minutes" >&2; exit 1; }
    fi
    echo "$sha256  $WORK/$commit.patch" | sha256sum -c - > /dev/null \
        || { echo "error: $commit.patch does not match its sha256" >&2; exit 1; }
    patch -s -d "$SRC" -p1 < "$WORK/$commit.patch"
    echo "   applied upstream fix ${commit:0:12}"
    applied+="${applied:+ }${commit:0:12}"
done
# --with-pinentry-pgm keeps gpg-agent on /usr/bin/pinentry, the alternative CodingBooth's
# pinentry setup repoints at a desktop flavour.
( cd "$SRC" \
  && ./configure --prefix=/usr/local --sysconfdir=/etc --localstatedir=/var \
       --with-pinentry-pgm=/usr/bin/pinentry --disable-doc --disable-tests \
  && make -j"$(nproc)" \
  && make install DESTDIR="$STAGE" ) > "$WORK/build.log" 2>&1 || { tail -80 "$WORK/build.log"; exit 1; }

# Everything has to land under the prefix: the asset carries /usr/local only.
outside=$(cd "$STAGE" && find . -mindepth 1 -maxdepth 2 ! -path ./usr ! -path ./usr/local)
[[ -z "$outside" ]] || { echo "error: make install wrote outside /usr/local: $outside" >&2; exit 1; }

echo "==> Testing"
# The binaries find each other through paths fixed at /usr/local, so test them there; the
# build runs in a throwaway container.
cp -a "$STAGE/usr/local/." /usr/local/
hash -r
for b in bin/gpg bin/gpg-agent bin/gpgsm bin/gpgconf bin/dirmngr libexec/keyboxd libexec/scdaemon; do
    libs_missing="$(ldd "/usr/local/$b" | grep 'not found' || true)"
    [[ -z "$libs_missing" ]] || { echo "error: $b: missing shared libraries: $libs_missing" >&2; exit 1; }
    # configure drops a component whose dependency it cannot find (dirmngr without GnuTLS,
    # keyboxd without SQLite) and still succeeds.
    /usr/local/$b --version 2>/dev/null | head -1 | grep -qF "$VERSION" \
        || { echo "error: /usr/local/$b is missing or does not report $VERSION" >&2; exit 1; }
done
/usr/local/bin/gpg --version | head -1
# A post-quantum (ML-KEM) key, then an encrypt/decrypt and a sign/verify round trip.
export GNUPGHOME="$WORK/testhome"
mkdir -m 700 "$GNUPGHOME"
gpg() { /usr/local/bin/gpg --batch --pinentry-mode loopback --passphrase '' "$@"; }
gpg --quiet --quick-gen-key booth@example.com pqc default never 2>/dev/null
gpg --list-keys --with-colons booth@example.com | grep -q '^sub:.*:ky768\|^sub:.*:ky1024\|^sub:.*kyber' \
    || { gpg --list-keys booth@example.com; echo "error: no Kyber subkey on the pqc key" >&2; exit 1; }
echo 'hello from a booth' > "$WORK/msg"
gpg --quiet -r booth@example.com -o "$WORK/msg.gpg" --encrypt "$WORK/msg"
[[ "$(gpg --quiet --decrypt "$WORK/msg.gpg" 2>/dev/null)" == 'hello from a booth' ]] \
    || { echo "error: decrypting with the pqc key did not give the message back" >&2; exit 1; }
gpg --quiet -u booth@example.com -o "$WORK/msg.sig" --detach-sign "$WORK/msg"
gpg --quiet --verify "$WORK/msg.sig" "$WORK/msg" 2>/dev/null \
    || { echo "error: verifying a signature failed" >&2; exit 1; }
echo "   pqc key: encrypt/decrypt and sign/verify round trips work"
/usr/local/bin/gpgconf --kill all
# A secret key exported and imported into another home, no passphrase, has to decrypt there
# (T8469: 2.5.23 and 2.5.24 as released cannot).
export GNUPGHOME="$WORK/importhome"
mkdir -m 700 "$GNUPGHOME"
GNUPGHOME="$WORK/testhome" gpg --armor --export-secret-keys booth@example.com | gpg --quiet --import 2>/dev/null
/usr/local/bin/gpgconf --homedir "$WORK/testhome" --kill all
[[ "$(gpg --quiet --decrypt "$WORK/msg.gpg" 2>/dev/null)" == 'hello from a booth' ]] \
    || { echo "error: an imported secret key cannot decrypt (T8469)" >&2; exit 1; }
echo "   an imported secret key decrypts"
/usr/local/bin/gpgconf --kill all
unset GNUPGHOME
echo "smoke tests passed"

cp -a "$STAGE/usr/local/." "$PKG_DIR/"
cp "$SRC/COPYING" "$PKG_DIR/COPYING"
# The packages holding every shared library the binaries link, so an installer brings
# exactly those in on this Ubuntu.
for f in "$PKG_DIR"/bin/* "$PKG_DIR"/sbin/* "$PKG_DIR"/libexec/*; do
    [[ -f "$f" ]] && file -b "$f" | grep -q ELF || continue
    ldd "$f" | awk '$3 ~ /^\// { print $3 }'
done | LC_ALL=C sort -u | while read -r lib; do
    dpkg -S "$(readlink -f "$lib")" 2>/dev/null || dpkg -S "$lib"
done | cut -d: -f1 | LC_ALL=C sort -u > "$PKG_DIR/RUNTIME-DEPS.txt"
echo "   runtime packages: $(tr '\n' ' ' < "$PKG_DIR/RUNTIME-DEPS.txt")"
{
    echo "source:       $base/$tarball"
    echo "signature:    good, by GnuPG release key $trusted"
    echo "patches:      ${applied:-none}"
    echo "sha256:       $(sha256sum "$WORK/$tarball" | awk '{print $1}')"
    echo "compiler:     $(gcc --version | head -1)"
} >> "$BUILD_NOTES"
