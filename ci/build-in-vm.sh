#!/bin/sh
# Build the FreedomNAS packages and their signed catalogue inside FreeBSD's
# own VM image, from a Linux host, and leave the publishable files in a
# flat directory.
#
#   ci/build-in-vm.sh <out-dir>
#
# The FreeBSD guest is the one freedomnas-image-builder boots for the
# FreeBSD images (freebsd/mfsbsd.sh, QEMU backend), so the image builder's
# checkout must sit beside this one, like the five component checkouts the
# packages are built from. The guest runs ci/build-in-guest.sh and writes a
# tar of the result to the start of a scratch disk; this script reads it
# back from there.
#
# Environment:
#   SNAPSHOT=1           version the packages as <base>.<commit stamp>
#   SIGNING_KEY=<file>   RSA private key; without it the catalogue is unsigned
#   FREEBSD_RELEASE      the release whose VM image builds them (15.1-RELEASE)
#   MODULES              community module checkouts beside this one to build
#                        too, e.g. "freedomnas-containers"
#   QEMU_MEM, QEMU_SMP   the guest's memory (MiB) and processors: 12288 and 4,
#                        a GitHub runner's, since the ports build QEMU
#   QEMU_GUEST_TIMEOUT   seconds the guest may take (10800)
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC_ROOT="$(dirname "$REPO_DIR")"
OUT="${1:?usage: ci/build-in-vm.sh <out-dir>}"
COMPONENTS="freedomnas-profiles freedomnas-core freedomnas-docs freedomnas-webui freedomnas-installer"

SCRIPT_DIR="$SRC_ROOT/freedomnas-image-builder/freebsd"
[ -f "$SCRIPT_DIR/mfsbsd.sh" ] || { echo "build-in-vm.sh: no freedomnas-image-builder beside $REPO_DIR" >&2; exit 1; }
FREEBSD_BACKEND=qemu
FREEBSD_BUILD_ENV=vm
QEMU_MEM="${QEMU_MEM:-12288}"
QEMU_SMP="${QEMU_SMP:-4}"
QEMU_GUEST_TIMEOUT="${QEMU_GUEST_TIMEOUT:-10800}"
export QEMU_MEM QEMU_SMP QEMU_GUEST_TIMEOUT
. "$SCRIPT_DIR/mfsbsd.sh"

for tool in git tar curl xz python3 qemu-system-x86_64 xorriso; do
    command -v "$tool" >/dev/null || { echo "build-in-vm.sh: $tool not found" >&2; exit 1; }
done

SEED="$(mktemp -d)"
DISK="$(mktemp -d)/scratch.img"
trap 'rm -rf "$SEED" "$(dirname "$DISK")"' EXIT

echo "=== [1/4] Sources ==="
mkdir -p "$SEED/src"
for name in $COMPONENTS ${MODULES:-}; do
    [ -d "$SRC_ROOT/$name/.git" ] || { echo "build-in-vm.sh: no checkout at $SRC_ROOT/$name" >&2; exit 1; }
    git -c safe.directory='*' clone -q --depth 1 "file://$SRC_ROOT/$name" "$SEED/src/$name"
    echo "    $name $(git -C "$SEED/src/$name" log -1 --format='%h %cd' --date=iso-strict)"
done
mkdir -p "$SEED/src/freedomnas-freebsd"
cp -R "$REPO_DIR/bin" "$REPO_DIR/ci" "$REPO_DIR/ports" "$SEED/src/freedomnas-freebsd/"
tar -cf "$SEED/src.tar" -C "$SEED/src" .
rm -rf "$SEED/src"
if [ -n "${SIGNING_KEY:-}" ]; then
    cp "$SIGNING_KEY" "$SEED/signing.key"
fi
printf 'SNAPSHOT="%s"\nMODULES="%s"\n' "${SNAPSHOT:-}" "${MODULES:-}" > "$SEED/env.sh"
cp "$REPO_DIR/ci/build-in-guest.sh" "$SEED/build-in-guest.sh"

echo "=== [2/4] Scratch disk ==="
truncate -s 1G "$DISK"

echo "=== [3/4] FreeBSD $FREEBSD_RELEASE VM image ==="
fnas_fetch_build_env

echo "=== [4/4] Building in the guest ==="
fnas_run_guest "$DISK" "$SEED" build-in-guest.sh

mkdir -p "$OUT"
tar -xf "$DISK" -C "$OUT" 2>/dev/null || true
if [ -f "$OUT/guest-build.log" ]; then
    mv "$OUT/guest-build.log" "$OUT/../guest-build.log"
    tail -n 40 "$OUT/../guest-build.log"
fi
[ -f "$OUT/meta.conf" ] || { echo "build-in-vm.sh: the guest wrote no catalogue -- the build failed" >&2; exit 1; }
ls -l "$OUT"
