#!/bin/sh
# Move a Pi-hole port to another upstream release, or its next/ series to
# upstream's development branch of today
#
#   bin/update-pihole.sh ftl 6.9      # dns/pihole-ftl to FTL v6.9
#   bin/update-pihole.sh core 6.6     # dns/pihole to Pi-hole v6.6
#   bin/update-pihole.sh web 6.7      # the web interface dns/pihole ships
#   bin/update-pihole.sh ftl next     # next/ onto FTL's development branch
#
# FTL and core carry FreedomNAS's FreeBSD changes twice, one patch per change:
# files/patch-* against the release the port builds, which the ports framework
# applies, and next/patch-* against upstream's development branch (the commit
# is in next/UPSTREAM), where the next release is made. A new release starts
# from next/ when there is one, as it already follows that release's code.
#
# The series is applied with `git am -3` on a checkout of the target; a patch
# that does not apply stops there, in a directory this prints: fix the
# conflict, `git am --continue` until the series is done, then
#
#   bin/update-pihole.sh --export ftl <that directory>
#
# writes the patches back: for a release with the version, the release hash
# and distinfo, for next/ with the development commit.
# Runs anywhere with git, curl and sha256sum (or FreeBSD's sha256).
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

usage() {
    echo "usage: $0 ftl|core <version>|next" >&2
    echo "       $0 web <version>" >&2
    echo "       $0 --export ftl|core <directory>" >&2
    exit 2
}

export_only=""
if [ "${1:-}" = --export ]; then
    export_only=yes
    shift
fi
[ $# -eq 2 ] || usage
what=$1
case $what in
    ftl) port=pihole-ftl project=FTL hashvar=FTL_HASH ;;
    core) port=pihole project=pi-hole hashvar=CORE_HASH ;;
    web) port=pihole project=web hashvar="" ;;
    *) usage ;;
esac
PORT_DIR="$REPO_DIR/ports/dns/$port"
NEXT_DIR="$PORT_DIR/next"

sha256_of() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    else
        sha256 -q "$1"
    fi
}

set_var() {
    sed -i.bak "s|^\($1=[[:space:]]*\).*|\1$2|" "$PORT_DIR/Makefile"
    rm -f "$PORT_DIR/Makefile.bak"
}

bump_revision() {
    if grep -q '^PORTREVISION=' "$PORT_DIR/Makefile"; then
        awk '/^PORTREVISION=/ { sub(/[0-9]+$/, $2 + 1) } { print }' \
            "$PORT_DIR/Makefile" > "$PORT_DIR/Makefile.new"
        mv "$PORT_DIR/Makefile.new" "$PORT_DIR/Makefile"
    else
        sed -i.bak "/^DISTVERSION=/a\\
PORTREVISION=	1
" "$PORT_DIR/Makefile"
        rm -f "$PORT_DIR/Makefile.bak"
    fi
}

# The GitHub tarball of pi-hole/$project v$1, as USE_GITHUB fetches it
update_distinfo() {
    name="$port/pi-hole-$project-v$1_GH0.tar.gz"
    tarball=$(mktemp)
    curl -sfL -o "$tarball" "https://codeload.github.com/pi-hole/$project/tar.gz/v$1"
    sum=$(sha256_of "$tarball")
    size=$(wc -c < "$tarball" | tr -d ' ')
    rm -f "$tarball"
    {
        echo "TIMESTAMP = $(date +%s)"
        grep -v -e '^TIMESTAMP' -e "/pi-hole-$project-v" "$PORT_DIR/distinfo" || true
        echo "SHA256 ($name) = $sum"
        echo "SIZE ($name) = $size"
    } > "$PORT_DIR/distinfo.new"
    mv "$PORT_DIR/distinfo.new" "$PORT_DIR/distinfo"
}

# Write the series on top of $2 in checkout $1 to directory $3 as patch-*
write_series() {
    out=$(mktemp -d)
    git -C "$1" format-patch -q --no-prefix --no-renames --binary \
        --zero-commit --no-signature -N -o "$out" "$2..HEAD"
    mkdir -p "$3"
    rm -f "$3"/patch-*
    for patch in "$out"/*.patch; do
        mv "$patch" "$3/patch-${patch##*/}"
    done
    rmdir "$out"
}

export_patches() {
    work=$1
    target=$(cat "$work/.git/freedomnas-target")
    if [ "$target" = next ]; then
        base=$(git -C "$work" rev-parse upstream-development)
        write_series "$work" "$base" "$NEXT_DIR"
        echo "development $(git -C "$work" rev-parse --short=8 "$base")" > "$NEXT_DIR/UPSTREAM"
        echo "ports/dns/$port/next: development $(cut -d' ' -f2 "$NEXT_DIR/UPSTREAM") with $(ls "$NEXT_DIR"/patch-* | wc -l | tr -d ' ') patches"
        return
    fi
    release=$target
    write_series "$work" "$release" "$PORT_DIR/files"
    if ! grep -q "^DISTVERSION=[[:space:]]*${release#v}\$" "$PORT_DIR/Makefile"; then
        set_var DISTVERSION "${release#v}"
        sed -i.bak '/^PORTREVISION=/d' "$PORT_DIR/Makefile"
        rm -f "$PORT_DIR/Makefile.bak"
    fi
    set_var "$hashvar" "$(git -C "$work" rev-parse --short=8 "$release^{commit}")"
    if [ "$what" = ftl ]; then
        set_var FTL_DATE "$(git -C "$work" log -1 --format=%cs "$release")"
    fi
    update_distinfo "${release#v}"
    echo "ports/dns/$port: ${release} with $(ls "$PORT_DIR"/files/patch-* | wc -l | tr -d ' ') patches"
}

if [ -n "$export_only" ]; then
    [ "$what" != web ] || usage
    export_patches "$2"
    exit
fi

version=${2#v}
if [ "$what" = web ]; then
    [ "$version" != next ] || usage
    set_var WEB_VERSION "$version"
    bump_revision
    update_distinfo "$version"
    echo "ports/dns/$port: web v$version"
    exit
fi

series="$PORT_DIR/files"
if [ -d "$NEXT_DIR" ]; then
    series="$NEXT_DIR"
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/update-pihole-$what.XXXXXX")
git clone -q --filter=blob:none "https://github.com/pi-hole/$project.git" "$work"
if [ "$version" = next ]; then
    git -C "$work" checkout -q -b freedomnas origin/development
    git -C "$work" tag upstream-development
    echo next > "$work/.git/freedomnas-target"
else
    git -C "$work" checkout -q -b freedomnas "v$version"
    echo "v$version" > "$work/.git/freedomnas-target"
fi
if ! git -C "$work" am -q -3 -p0 "$series"/patch-*; then
    echo >&2
    echo "A patch of ${series#"$REPO_DIR"/} does not apply to $project $2. In $work:" >&2
    echo "  fix the conflict, git add, git am --continue (until the series is done)" >&2
    echo "  then: $0 --export $what $work" >&2
    exit 1
fi
export_patches "$work"
rm -rf "$work"
