#!/bin/sh
# Publish a flat catalogue (ci/build-in-vm.sh) as the assets of the release
# pkg-<major>-<group> of this GitHub repository:
#
#   https://github.com/FreedomNAS/freedomnas-freebsd/releases/download/pkg-15-dev
#
# which is the url of a FreeBSD pkg repository. Every package is uploaded
# again (the catalogue records each one's checksum, and a rebuilt port keeps
# its name), the catalogue last; then the files it no longer lists are
# removed.
#
#   GH_TOKEN=<token> GROUP=dev|main MAJOR=15 sh bin/publish-github.sh <dir>
set -eu

DIR="${1:?usage: bin/publish-github.sh <dir>}"
GH_REPO="${GH_REPO:-FreedomNAS/freedomnas-freebsd}"
GROUP="${GROUP:-dev}"
MAJOR="${MAJOR:-15}"
TAG="pkg-$MAJOR-$GROUP"
BASE="https://github.com/$GH_REPO/releases/download/$TAG"
export GH_REPO

: "${GH_TOKEN:?set GH_TOKEN to a token that can write this repository's releases}"
[ -f "$DIR/meta.conf" ] || { echo "publish-github.sh: no catalogue in $DIR" >&2; exit 1; }
command -v gh >/dev/null || { echo "publish-github.sh: gh not found" >&2; exit 1; }

for f in "$DIR"/*; do
    case "$(basename "$f")" in
        *[!A-Za-z0-9._+-]*) echo "publish-github.sh: $(basename "$f") has a character GitHub renames" >&2; exit 1 ;;
    esac
done

gh release view "$TAG" >/dev/null 2>&1 || gh release create "$TAG" --latest=false \
    --title "pkg repository (FreeBSD $MAJOR, $GROUP)" \
    --notes "The FreedomNAS pkg repository for FreeBSD $MAJOR, $GROUP channel: url: \"$BASE\""
before="$(gh release view "$TAG" --json assets --jq '.assets[].name')"

packages=""
catalogue=""
for f in "$DIR"/*; do
    case "$(basename "$f")" in
        meta.conf|packagesite.*|data.*|meta.*|filesite.*) catalogue="$catalogue $f" ;;
        *.pkg) packages="$packages $f" ;;
        *) catalogue="$catalogue $f" ;;
    esac
done

echo "==> packages"
[ -z "$packages" ] || gh release upload "$TAG" $packages --clobber
echo "==> catalogue"
gh release upload "$TAG" $catalogue --clobber

for old in $before; do
    [ -e "$DIR/$old" ] && continue
    echo "==> removing superseded $old"
    gh release delete-asset "$TAG" "$old" -y
done

echo
echo "Published to $BASE"
