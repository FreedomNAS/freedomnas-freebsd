#!/bin/sh
# Runs inside FreeBSD's VM image (ci/build-in-vm.sh): builds the packages
# with bin/build-freedomnas-pkgs.sh and the ports with bin/build-ports.sh, writes a flat signed catalogue and puts
# a tar of it at the start of the scratch disk. Ends with `poweroff` either
# way; on failure the scratch disk stays empty.
#
# The catalogue is flat -- the packages beside meta.conf and packagesite.pkg,
# not under All/ -- because Codeberg's generic registry, where it is
# published, has no directories.
set -eu

SEED=/fnas-seed
WORK=/fnas-build
. "$SEED/env.sh"

DISK="${FNAS_TARGET_DISK:-/dev/vtbd1}"
LOG=/tmp/guest-build.log
exec > "$LOG" 2>&1

log() { echo "guest-pkg: $*"; }
fail() {
    log "FAILED: $*"
    tar -cf /tmp/result.tar -C /tmp guest-build.log && dd if=/tmp/result.tar of="$DISK" bs=1m conv=sync
    poweroff
    exit 1
}

[ -e "$DISK" ] || fail "no scratch disk $DISK"

IFACE=$(ifconfig -l ether | awk '{print $1}')
ifconfig "$IFACE" | grep -q 'inet ' || dhclient "$IFACE" || fail "dhclient $IFACE"

mkdir -p "$WORK"
mount -t tmpfs tmpfs "$WORK" || fail "mount tmpfs on $WORK"
tar -xf "$SEED/src.tar" -C "$WORK" || fail "extract the sources"

log "=== Build tools ==="
export ASSUME_ALWAYS_YES=yes
pkg bootstrap -f >/dev/null 2>&1 || true
pkg update -f || fail "pkg update"
flavor=$(pkg rquery -U '%dn' python3 | sed -n 's/^python\([0-9]*\)$/py\1/p' | head -n 1)
[ -n "$flavor" ] || fail "no python3 flavor in the FreeBSD repository"
pkg install -y git python3 "$flavor-mkdocs-material" || fail "pkg install the build tools"

log "=== Packages ==="
git config --global --add safe.directory '*'
cd "$WORK/freedomnas-freebsd"
OUT="$WORK/out" SNAPSHOT="$SNAPSHOT" sh bin/build-freedomnas-pkgs.sh || fail "build-freedomnas-pkgs.sh"
if [ -n "${MODULES:-}" ]; then
    # shellcheck disable=SC2086
    OUT="$WORK/out" SNAPSHOT="$SNAPSHOT" sh bin/build-freedomnas-pkgs.sh $MODULES || fail "build-freedomnas-pkgs.sh $MODULES"
fi

log "=== Ports ==="
OUT="$WORK/out" PORTSDIR="$WORK/ports" sh bin/build-ports.sh || fail "build-ports.sh"

log "=== Catalogue ==="
FLAT="$WORK/flat"
mkdir -p "$FLAT"
cp "$WORK"/out/*/latest/All/*.pkg "$FLAT/" || fail "no package was built"
if [ -f "$SEED/signing.key" ]; then
    cp "$SEED/signing.key" "$WORK/signing.key"
    chmod 600 "$WORK/signing.key"
    pkg repo "$FLAT" "$WORK/signing.key" || fail "pkg repo (signed)"
    openssl rsa -in "$WORK/signing.key" -pubout -out "$FLAT/freedomnas.pub" 2>/dev/null || fail "public key"
    rm -f "$WORK/signing.key"
else
    pkg repo "$FLAT" || fail "pkg repo"
fi
ls -l "$FLAT"

log "done"
cp "$LOG" "$FLAT/guest-build.log"
tar -cf "$WORK/result.tar" -C "$FLAT" . || fail "tar the catalogue"
dd if="$WORK/result.tar" of="$DISK" bs=1m conv=sync || fail "write the result to $DISK"
poweroff
