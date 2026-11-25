#!/bin/sh
# Build the ports under ports/ into packages, beside the ones
# build-freedomnas-pkgs.sh drops: $OUT/ports/latest/All/<name>-<version>.pkg
#
#   bin/build-ports.sh                    # every port, in BUILD_ORDER
#   bin/build-ports.sh dns/pihole-ftl     # one of them
#   bin/build-ports.sh emulators/qemu@nox11   # one flavor of a port
#   PORTSDIR=/tmp/ports bin/build-ports.sh
#
# The ports framework comes from a shallow, sparse checkout of FreeBSD's ports
# tree (Mk, Templates, Keywords) on the branch the machine's packages come
# from: the current quarterly one (2026Q4) for a quarterly repository, main
# otherwise, plus lang/ for the Perl and Python versions USES=perl5 and
# USES=python read. Each port is copied into it and its dependencies are installed as
# packages from the FreeBSD repository, so only the ports here are compiled.
# A port that needs another one of these (dns/pihole needs dns/pihole-ftl)
# comes after it in BUILD_ORDER, and the package just built is installed for
# it. NOCLEANDEPENDS keeps `make clean` of a port from cleaning the ports it
# depends on, and with them the packages just built there.
#
# sysutils/freedomnas-nvmm is a kernel module: it needs the kernel sources,
# installed from the FreeBSD-base (pkgbase) repository when /usr/src/sys is
# missing. emulators/qemu needs it (libnvmm), so it comes first.
#
# Runs on FreeBSD as root, after a `pkg update`.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${OUT:-$REPO_DIR/out}"
PORTSDIR="${PORTSDIR:-/usr/ports}"
BUILD_ORDER="sysutils/freedomnas-nvmm emulators/qemu@nox11 dns/pihole-ftl dns/pihole"
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
    git -C "$PORTSDIR" sparse-checkout set Mk Templates Keywords lang
fi

if [ ! -f /usr/src/sys/Makefile ]; then
    echo "=== Kernel sources (FreeBSD-src-sys) ==="
    mkdir -p /usr/local/etc/pkg/repos
    [ -f /usr/local/etc/pkg/repos/FreeBSD-base.conf ] ||
        echo 'FreeBSD-base: { enabled: yes }' > /usr/local/etc/pkg/repos/FreeBSD-base.conf
    pkg update -r FreeBSD-base
    pkg install -y -r FreeBSD-base FreeBSD-src-sys
fi

export BATCH=yes PORTSDIR
DEST="$OUT/ports/latest/All"
mkdir -p "$DEST"

for entry in $PORTS; do
    port=${entry%@*}
    flavor=""
    [ "$port" = "$entry" ] || flavor=${entry#*@}
    [ -f "$REPO_DIR/ports/$port/Makefile" ] || { echo "build-ports.sh: no port $port" >&2; exit 1; }
    echo "=== $entry ==="
    rm -rf "${PORTSDIR:?}/$port"
    mkdir -p "$PORTSDIR/$(dirname "$port")"
    cp -R "$REPO_DIR/ports/$port" "$PORTSDIR/$port"

    # A dependency "name>=version:origin" is installed by its package name,
    # which carries the flavor (py312-wheel); a bare origin with flavors
    # (devel/py-wheel) would bring every Python's.
    deps=""
    for dep in $(make -C "$PORTSDIR/$port" ${flavor:+FLAVOR="$flavor"} -V FETCH_DEPENDS -V EXTRACT_DEPENDS \
            -V PATCH_DEPENDS -V BUILD_DEPENDS -V LIB_DEPENDS -V RUN_DEPENDS | tr ' ' '\n' | sort -u); do
        first=${dep%%:*}
        origin=${dep#*:}
        origin=${origin%%:*}
        origin=${origin%@*}
        [ -n "$origin" ] && [ "$origin" != "$dep" ] || continue
        [ -d "$REPO_DIR/ports/$origin" ] && continue
        case "$first" in
        *[\<\>=]*) deps="$deps ${first%%[<>=]*}" ;;
        *) deps="$deps $origin" ;;
        esac
    done
    # shellcheck disable=SC2086
    deps=$(printf '%s\n' $deps | sort -u | xargs)
    if [ -n "$deps" ]; then
        # shellcheck disable=SC2086
        pkg install -y $deps
    fi

    make -C "$PORTSDIR/$port" ${flavor:+FLAVOR="$flavor"} NOCLEANDEPENDS=yes clean package
    for pkgfile in "$PORTSDIR/$port"/work*/pkg/*.pkg; do
        cp "$pkgfile" "$DEST/"
        pkg add -f "$pkgfile"
    done
done

ls -l "$DEST"
