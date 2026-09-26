#!/bin/sh
# Print the version a package should be built with.
#
#   bin/version.sh ../freedomnas-core              -> 1.0
#   bin/version.sh --snapshot ../freedomnas-core   -> 1.0.202609261432
#
# The base version is the upstream half of debian/changelog, the same number
# freedomnas-deb publishes, so a release carries one version everywhere.
# A snapshot appends the commit's date and time: pkg compares the versions
# number by number, so `1.0.<stamp>` sorts after `1.0` and below `1.1`, and
# every rebuild of a small change gets a version of its own. The commit hash
# cannot go in the version (its letters would break that ordering); the
# package carries it as an annotation instead.
set -eu

snapshot=0
if [ "${1:-}" = "--snapshot" ]; then
    snapshot=1
    shift
fi
src="${1:?usage: version.sh [--snapshot] <source-dir>}"
[ -f "$src/debian/changelog" ] || { echo "version.sh: no debian/changelog in $src" >&2; exit 1; }

base="$(sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$src/debian/changelog")"
upstream="${base%-*}"
[ -n "$upstream" ] || { echo "version.sh: cannot read the version from $src/debian/changelog" >&2; exit 1; }

if [ "$snapshot" = 0 ]; then
    printf '%s\n' "$upstream"
    exit 0
fi

command -v git >/dev/null || { echo "version.sh: git not found" >&2; exit 1; }
git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "version.sh: $src is not a git checkout, so there is no commit to name" >&2
    exit 1
}

stamp="$(TZ=UTC git -C "$src" log -1 --format=%cd --date=format-local:%Y%m%d%H%M)"
printf '%s.%s\n' "$upstream" "$stamp"
