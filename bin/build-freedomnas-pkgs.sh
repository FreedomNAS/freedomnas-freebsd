#!/bin/sh
# Build the FreedomNAS packages from the checkouts beside this repository and
# drop them into the repository tree.
#
#   bin/build-freedomnas-pkgs.sh                     # all five
#   bin/build-freedomnas-pkgs.sh freedomnas-webui    # one of them
#   SNAPSHOT=1 bin/build-freedomnas-pkgs.sh          # ...at 1.0.<stamp>
#   ABI=FreeBSD:14 bin/build-freedomnas-pkgs.sh      # for another major version
#   bin/build-freedomnas-pkgs.sh freedomnas-containers   # a community module
#
# A community module's repository (freedomnas-<id>) becomes the package
# freedomnas-module-<id>, the name the WebUI's Plugins page searches for.
#
# Nothing here is compiled but the documentation, which mkdocs turns into a
# static site; the other packages are Python and JSON. Each is a staging
# directory laid out the way the .deb, the PKGBUILD and the Gentoo
# ebuild lay it out, handed to `pkg create` with a manifest. The root the
# files go under is not decided here: it is `paths.install_root` in
# freedomnas-profiles' os/os-freebsd.json (/usr/local/lib/freedomnas), and
# every installed component finds the others relative to itself.
#
# freedomnas-core is not built as a wheel: its pyproject.toml needs
# setuptools 77, and FreeBSD's is older. It is installed the way every
# edition installs it — the package directory under <root>/core, put on
# sys.path by a .pth file.
#
# The dependencies are resolved against the FreeBSD repository this machine
# uses, so it runs on FreeBSD, after a `pkg update`.
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC_ROOT="$(dirname "$REPO_DIR")"
DEFAULT_COMPONENTS="freedomnas-profiles freedomnas-core freedomnas-docs freedomnas-webui freedomnas-installer"
COMPONENTS="${*:-$DEFAULT_COMPONENTS}"
OUT="${OUT:-$REPO_DIR/out}"
REPO_ARCH="${REPO_ARCH:-amd64}"
MAINTAINER="dev@freedomnas.io"

case " $COMPONENTS " in
*" freedomnas-docs "*)
    command -v mkdocs >/dev/null || {
        echo "build-freedomnas-pkgs.sh: mkdocs not found — pkg install $(pkg rquery -U '%dn' python3 | sed -n 's/^python\([0-9]*\)$/py\1/p' | head -n 1)-mkdocs-material" >&2
        exit 1
    }
    ;;
esac

for tool in pkg python3 git; do
    command -v "$tool" >/dev/null || {
        echo "build-freedomnas-pkgs.sh: $tool not found — this runs on FreeBSD" >&2
        exit 1
    }
done

ABI="${ABI:-$(pkg config abi | cut -d: -f1-2)}"
# The flavor the python3 metaport points at: python312 -> py312.
PYFLAVOR="${PYFLAVOR:-$(pkg rquery -U '%dn' python3 | sed -n 's/^python\([0-9]*\)$/py\1/p' | head -n 1)}"
[ -n "$PYFLAVOR" ] || { echo "build-freedomnas-pkgs.sh: cannot tell the default Python flavor — run pkg update" >&2; exit 1; }
SITE_DIR="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
ROOT="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["paths"]["install_root"])' \
    "$SRC_ROOT/freedomnas-profiles/os/os-freebsd.json")"

ALL="$OUT/$ABI:$REPO_ARCH/latest/All"
install -d "$ALL"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

version_of() {
    "$REPO_DIR/bin/version.sh" ${SNAPSHOT:+--snapshot} "$SRC_ROOT/$1"
}

# name -> "name": {origin, version}, from the repository for a FreeBSD
# package and from the sibling checkout for a FreedomNAS one.
dep_entry() {
    case "$1" in
    freedomnas-*)
        origin="sysutils/$1"
        version="$(version_of "$1")"
        ;;
    *)
        line="$(pkg rquery -U '%o %v' "$1" | head -n 1)"
        [ -n "$line" ] || { echo "build-freedomnas-pkgs.sh: $1 is not in the FreeBSD repository" >&2; exit 1; }
        origin="${line% *}"
        version="${line#* }"
        ;;
    esac
    printf '"%s": {"origin": "%s", "version": "%s"}' "$1" "$origin" "$version"
}

deps_json() {
    sep=""
    for dep in "$@"; do
        printf '%s%s' "$sep" "$(dep_entry "$dep")"
        sep=", "
    done
}

strip_bytecode() {
    find "$1" -name __pycache__ -type d -prune -exec rm -rf {} +
}

stage_profiles() {
    dest="$1$ROOT/profiles"
    install -d "$dest"
    ( cd "$2" && cp -R os init installer storage network shares users packages assets "$dest/" )
}

stage_core() {
    dest="$1$ROOT/core/freedomnas"
    install -d "$dest"
    ( cd "$2" && cp -R *.py modules "$dest/" )
    rm -f "$dest/conftest.py"
    install -d "$1$SITE_DIR"
    echo "$ROOT/core" > "$1$SITE_DIR/freedomnas-core.pth"
    install -d "$1/usr/local/bin"
    install -m 755 "$2/bin/freedomnas" "$1/usr/local/bin/freedomnas"
}

stage_docs() {
    dest="$1$ROOT/docs"
    install -d "$dest"
    FREEDOMNAS_DOCS_VERSION="$label" mkdocs build --quiet \
        --config-file "$2/mkdocs.yml" --site-dir "$dest"
}

stage_webui() {
    dest="$1$ROOT/webui"
    install -d "$dest/bin"
    ( cd "$2" && cp -R api frontend websocket "$dest/" )
    echo "$label" > "$dest/VERSION"
    # Shared verbatim with the image builder, so they stay in
    # freedomnas-profiles/assets rather than being copied here.
    ln -s ../../profiles/assets/firstboot.sh "$dest/bin/firstboot.sh"
    ln -s ../../profiles/assets/supervisor.sh "$dest/bin/supervisor.sh"
}

stage_module() {
    install -d "$1$ROOT/modules" "$1$ROOT/profiles"
    cp -R "$2/modules/$3" "$1$ROOT/modules/$3"
    cp -R "$2/profiles/$3" "$1$ROOT/profiles/$3"
}

stage_containers() {
    stage_module "$1" "$2" containers
}

stage_proxy() {
    stage_module "$1" "$2" proxy
}

stage_installer() {
    dest="$1$ROOT/installer"
    install -d "$dest/lib" "$1/usr/local/bin"
    install -m 755 "$2/setup.py" "$dest/setup.py"
    install -m 644 "$2"/lib/*.py "$dest/lib/"
    ln -s "$ROOT/installer/setup.py" "$1/usr/local/bin/freedomnas-install"
}

for name in $COMPONENTS; do
    src="$SRC_ROOT/$name"
    [ -d "$src" ] || { echo "build-freedomnas-pkgs.sh: no checkout at $src" >&2; exit 1; }

    licenses="MPL20"
    pkgname="$name"
    case "$name" in
    freedomnas-profiles)
        comment="FreedomNAS OS profiles, the JSON translator layer"
        deps=""
        ;;
    freedomnas-core)
        comment="FreedomNAS core engine, OS-agnostic storage appliance"
        deps="freedomnas-profiles python3 $PYFLAVOR-pyyaml $PYFLAVOR-cryptography"
        ;;
    freedomnas-docs)
        comment="FreedomNAS documentation, for reading offline in the WebUI"
        deps=""
        licenses="MPL20 OFL11"
        ;;
    freedomnas-webui)
        comment="FreedomNAS web interface"
        deps="freedomnas-core freedomnas-profiles freedomnas-docs python3 $PYFLAVOR-fastapi $PYFLAVOR-uvicorn $PYFLAVOR-websockets $PYFLAVOR-Jinja2 $PYFLAVOR-python-pam $PYFLAVOR-pyyaml"
        ;;
    freedomnas-installer)
        comment="Profile-driven FreedomNAS installer"
        deps="freedomnas-core freedomnas-profiles python3 cdialog curl"
        ;;
    freedomnas-containers)
        pkgname=freedomnas-module-containers
        comment="FreedomNAS containers: AppJail jails on ZFS datasets, apps and a catalogue"
        deps="freedomnas-core freedomnas-webui"
        ;;
    freedomnas-proxy)
        pkgname=freedomnas-module-proxy
        comment="FreedomNAS reverse proxy: Caddy with HTTPS for every web app"
        deps="freedomnas-core freedomnas-webui"
        ;;
    *)
        echo "build-freedomnas-pkgs.sh: unknown component $name" >&2
        exit 1
        ;;
    esac

    version="$(version_of "$name")"
    base="$("$REPO_DIR/bin/version.sh" "$src")"
    case "$version" in
    "$base") label="$version" ;;
    *) label="$base+${version#"$base".}" ;;
    esac
    echo "==> $pkgname $version ($ABI, $ROOT)"

    stage="$WORK/$name/stage"
    install -d "$stage"
    "stage_${name#freedomnas-}" "$stage" "$src"
    strip_bytecode "$stage"
    # Shipped in the package, so Python never writes a __pycache__ of its
    # own that `pkg delete` would leave behind.
    python3 -m compileall -q --invalidation-mode checked-hash \
        -s "$stage" -p / "$stage$ROOT" >/dev/null
    if [ -f "$src/README.md" ]; then
        install -d "$stage/usr/local/share/doc/$pkgname"
        install -m 644 "$src/README.md" "$stage/usr/local/share/doc/$pkgname/README.md"
    fi

    NAME="$pkgname" REPO="$name" VERSION="$version" COMMENT="$comment" ABI="$ABI" MAINTAINER="$MAINTAINER" LICENSES="$licenses" \
    DEPS="{$(deps_json $deps)}" COMMIT="$(git -C "$src" log -1 --format=%H 2>/dev/null || echo unknown)" \
    README="$src/README.md" python3 - > "$WORK/$name/manifest" <<'EOF'
import json, os, re
e = os.environ
try:
    lines = open(e["README"], encoding="utf-8").read().splitlines()
except FileNotFoundError:
    lines = []
para = []
for l in lines:
    if para and l.strip():
        para.append(l.strip())
    elif para:
        break
    elif l.strip() and not l.startswith(("#", "!", "[", "<", "`", "|")):
        para.append(l.strip())
desc = re.sub(r"\[([^]]*)\]\([^)]*\)", r"\1", " ".join(para)) or e["COMMENT"]
print(json.dumps({
    "name": e["NAME"],
    "origin": "sysutils/" + e["NAME"],
    "version": e["VERSION"],
    "comment": e["COMMENT"],
    "desc": desc,
    "maintainer": e["MAINTAINER"],
    "www": "https://codeberg.org/FreedomNAS/" + e["REPO"],
    "abi": e["ABI"] + ":*",
    "prefix": "/usr/local",
    "licenselogic": "single" if len(e["LICENSES"].split()) == 1 else "and",
    "licenses": e["LICENSES"].split(),
    "categories": ["sysutils"],
    "deps": json.loads(e["DEPS"]),
    "annotations": {"freedomnas_commit": e["COMMIT"]},
}, indent=2))
EOF

    {
        echo "@owner root"
        echo "@group wheel"
        ( cd "$stage" && find . \( -type f -o -type l \) ) | sed 's|^\.||' | sort
        ( cd "$stage" && find ".$ROOT" -type d; find ./usr/local/share/doc -mindepth 1 -type d 2>/dev/null ) \
            | sed 's|^\.|@dir |' | sort -r
    } > "$WORK/$name/plist"

    rm -f "$ALL/$pkgname"-[0-9]*.pkg
    pkg create -M "$WORK/$name/manifest" -p "$WORK/$name/plist" -r "$stage" -o "$ALL"
    echo "    $ALL/$pkgname-$version.pkg"
done

echo "==> Now run bin/make-repo.sh"
