#!/bin/sh
# Write the pkg catalogue for every ABI tree under out/.
#
#   bin/make-repo.sh                               # unsigned, for a local test
#   SIGNING_KEY=freedomnas.key bin/make-repo.sh    # signed, for publishing
#   bin/make-repo.sh --new-key freedomnas.key      # make the key pair first
#
# `pkg repo` writes meta.conf, packagesite.pkg and data.pkg next to All/, and
# with a key it signs them. The private key never goes into git — this
# repository ignores *.key, and the public repository gets only the .pub,
# which is what a FreedomNAS machine checks the catalogue against.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${OUT:-$REPO_DIR/out}"

command -v pkg >/dev/null || { echo "make-repo.sh: pkg not found — this runs on FreeBSD" >&2; exit 1; }

if [ "${1:-}" = "--new-key" ]; then
    key="${2:?usage: make-repo.sh --new-key <file.key>}"
    [ -e "$key" ] && { echo "make-repo.sh: $key already exists" >&2; exit 1; }
    ( umask 077 && openssl genrsa -out "$key" 4096 )
    openssl rsa -in "$key" -pubout -out "${key%.key}.pub"
    echo "==> private: $key  public: ${key%.key}.pub"
    exit 0
fi

found=0
for latest in "$OUT"/*/latest; do
    [ -d "$latest/All" ] || continue
    found=1
    echo "==> $latest"
    if [ -n "${SIGNING_KEY:-}" ]; then
        pkg repo "$latest" "$SIGNING_KEY"
        openssl rsa -in "$SIGNING_KEY" -pubout -out "$OUT/freedomnas.pub" 2>/dev/null
    else
        pkg repo "$latest"
    fi
done
[ "$found" = 1 ] || { echo "make-repo.sh: nothing under $OUT — run bin/build-freedomnas-pkgs.sh first" >&2; exit 1; }
