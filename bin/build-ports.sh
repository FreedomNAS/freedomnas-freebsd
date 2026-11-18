#!/bin/sh
# Build the ports under ports/ into packages, beside the ones
# build-freedomnas-pkgs.sh drops: $OUT/ports/latest/All/<name>-<version>.pkg
#
#   bin/build-ports.sh                    # every port, in BUILD_ORDER
#   bin/build-ports.sh dns/pihole-ftl     # one of them
#   PORTSDIR=/tmp/ports bin/build-ports.sh
#
# The ports framework comes from a shallow, sparse checkout of FreeBSD's ports
# tree (Mk, Templates, Keywords) on the branch the machine's packages come
# from: the current quarterly one (2026Q4) for a quarterly repository, main
# otherwise. Each port is copied into it and its dependencies are installed as
# packages from the FreeBSD repository, so only the ports here are compiled.
# A port that needs another one of these (dns/pihole needs dns/pihole-ftl)
# comes after it in BUILD_ORDER, and the package just built is installed for
# it. NOCLEANDEPENDS keeps `make clean` of a port from cleaning the ports it
# depends on, and with them the packages just built there.
#
# Runs on FreeBSD as root, after a `pkg update`.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${OUT:-$REPO_DIR/out}"
PORTSDIR="${PORTSDIR:-/usr/ports}"
BUILD_ORDER="dns/pihole-ftl dns/pihole"
PORTS="${*:-$BUILD_ORDER}"

for tool in pkg git make; do
    command -v "$tool" >/dev/null || {
        echo "build-ports.sh: $tool not found — this runs on FreeBSD" >&2
        exit 1
    }
done

if [ ! -f "$PORTSDIR/Mk/bsd.port.mk" ]; then
    if pkg -vv | grep -q '/quarterly"'; then
        month=$(date +%m)
        branch="$(date +%Y)Q$(( (${month#0} - 1) / 3 + 1 ))"
    else
        branch=main
    fi
    echo "=== Ports framework ($branch) ==="
    for url in https://git.FreeBSD.org/ports.git https://github.com/freebsd/freebsd-ports.git; do
        git clone -q --depth 1 --filter=blob:none --sparse --branch "$branch" "$url" "$PORTSDIR" && break
        echo "build-ports.sh: $url unreachable, trying the next mirror" >&2
    done
    [ -f "$PORTSDIR/.git/HEAD" ] || { echo "build-ports.sh: no ports mirror reachable" >&2; exit 1; }
    git -C "$PORTSDIR" sparse-checkout set Mk Templates Keywords
fi

export BATCH=yes PORTSDIR
DEST="$OUT/ports/latest/All"
mkdir -p "$DEST"

for port in $PORTS; do
    [ -f "$REPO_DIR/ports/$port/Makefile" ] || { echo "build-ports.sh: no port $port" >&2; exit 1; }
    echo "=== $port ==="
    rm -rf "${PORTSDIR:?}/$port"
    mkdir -p "$PORTSDIR/$(dirname "$port")"
    cp -R "$REPO_DIR/ports/$port" "$PORTSDIR/$port"

    deps=""
    for origin in $(make -C "$PORTSDIR/$port" -V FETCH_DEPENDS -V EXTRACT_DEPENDS \
            -V PATCH_DEPENDS -V BUILD_DEPENDS -V LIB_DEPENDS -V RUN_DEPENDS \
            | tr ' ' '\n' | sed -n 's/^[^:]*:\([^:@]*\).*/\1/p' | sort -u); do
        [ -d "$REPO_DIR/ports/$origin" ] || deps="$deps $origin"
    done
    if [ -n "$deps" ]; then
        # shellcheck disable=SC2086
        pkg install -y $deps
    fi

    make -C "$PORTSDIR/$port" NOCLEANDEPENDS=yes clean package
    for pkgfile in "$PORTSDIR/$port"/work/pkg/*.pkg; do
        cp "$pkgfile" "$DEST/"
        pkg add -f "$pkgfile"
    done
done

ls -l "$DEST"
