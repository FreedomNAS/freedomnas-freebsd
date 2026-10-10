#!/bin/sh
# Publish a flat catalogue (ci/build-in-vm.sh) to Codeberg's generic
# registry, as the version <major>-<group> of the package freedomnas-freebsd:
#
#   https://codeberg.org/api/packages/FreedomNAS/generic/freedomnas-freebsd/15-dev
#
# which is the url of a FreeBSD pkg repository. The packages go first and
# the catalogue last, then the packages it no longer lists are removed.
#
#   GROUP=dev|main MAJOR=15 bin/publish-codeberg.sh <dir>
set -eu

DIR="${1:?usage: bin/publish-codeberg.sh <dir>}"
OWNER="${CODEBERG_OWNER:-FreedomNAS}"
GROUP="${GROUP:-dev}"
MAJOR="${MAJOR:-15}"
API="https://codeberg.org/api/v1/packages/$OWNER/generic/freedomnas-freebsd/$MAJOR-$GROUP"
BASE="${BASE:-https://codeberg.org/api/packages/$OWNER/generic/freedomnas-freebsd/$MAJOR-$GROUP}"

: "${CODEBERG_USER:?set CODEBERG_USER to your Codeberg username}"
: "${CODEBERG_TOKEN:?set CODEBERG_TOKEN to a token with the package scope}"
[ -f "$DIR/meta.conf" ] || { echo "publish-codeberg.sh: no catalogue in $DIR" >&2; exit 1; }

auth() { printf 'user = "%s:%s"\n' "$CODEBERG_USER" "$CODEBERG_TOKEN"; }

put() {
    status="$(auth | curl --config - -s -S -o /dev/null -w '%{http_code}' --upload-file "$1" "$BASE/$2")"
    case "$status" in
        200|201) echo "    uploaded $2" ;;
        *) echo "publish-codeberg.sh: upload of $2: HTTP $status" >&2; return 1 ;;
    esac
}

delete() {
    status="$(auth | curl --config - -s -S -o /dev/null -w '%{http_code}' -X DELETE "$BASE/$1")"
    case "$status" in
        200|204|404) ;;
        *) echo "publish-codeberg.sh: delete of $1: HTTP $status" >&2; return 1 ;;
    esac
}

before="$(curl -s "$API/files" | python3 -c 'import json, sys
try:
    files = json.load(sys.stdin)
except ValueError:
    files = []
print("\n".join(f["name"] for f in files if isinstance(f, dict)))')"

catalogue=""
for f in "$DIR"/*; do
    name="$(basename "$f")"
    case "$name" in
        *.pkg) ;;
        *) catalogue="$catalogue $name"; continue ;;
    esac
    case "$name" in
        meta.conf|packagesite.*|data.*|meta.*|filesite.*) catalogue="$catalogue $name"; continue ;;
    esac
    echo "==> $name"
    delete "$name"
    put "$f" "$name"
done

echo "==> catalogue"
for name in $catalogue; do
    delete "$name"
    put "$DIR/$name" "$name"
done

for old in $before; do
    [ -e "$DIR/$old" ] && continue
    echo "==> removing superseded $old"
    delete "$old"
done

echo
echo "Published to $BASE"
