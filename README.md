# freedomnas-freebsd

A pkg repository for FreedomNAS on FreeBSD: the five FreedomNAS packages,
built from the checkouts beside this one.

| Package | Depends on (FreeBSD's own repository) |
|---------|----------------------------------------|
| `freedomnas-profiles` | — |
| `freedomnas-core` | `python3`, `py312-pyyaml`, `py312-cryptography` |
| `freedomnas-docs` | — (built with `py312-mkdocs-material`) |
| `freedomnas-webui` | `freedomnas-docs`, `py312-fastapi`, `-uvicorn`, `-websockets`, `-Jinja2`, `-python-pam`, `-pyyaml` |
| `freedomnas-installer` | `python3`, `cdialog`, `curl` |

Everything else FreedomNAS installs on FreeBSD is already in FreeBSD's
repository, `sysutils/topgrade` included, or in the base system (ZFS,
bhyve, the NFS server, efibootmgr). The `py312` flavor is whatever the
`python3` metaport points at when the packages are built.

## Building

On FreeBSD, after `pkg update`, with the five FreedomNAS checkouts beside
this one and `python3`, `git` and — for freedomnas-docs —
`py312-mkdocs-material` installed:

```sh
bin/build-freedomnas-pkgs.sh                    # all five
bin/build-freedomnas-pkgs.sh freedomnas-webui   # one of them
SNAPSHOT=1 bin/build-freedomnas-pkgs.sh         # ...as 1.0.<yyyymmddhhmm>
ABI=FreeBSD:14 bin/build-freedomnas-pkgs.sh     # for another major version
bin/make-repo.sh --new-key freedomnas.key       # once: the signing key pair
SIGNING_KEY=freedomnas.key bin/make-repo.sh     # the signed catalogue
```

The version is the upstream half of each component's `debian/changelog`,
the same number freedomnas-deb publishes. Nothing is compiled but the
documentation, which mkdocs builds into a static site under `<root>/docs`
for the WebUI to serve offline; each package is a staging directory handed
to `pkg create`. The WebUI's `VERSION` file and the documentation carry the
FreedomNAS form of the version, `1.0+<yyyymmddhhmm>` for a snapshot, so the
documentation can tell whether it belongs to the same release. The packages are
architecture-independent (`FreeBSD:15:*`), but pkg still refuses a package
built for another major version, so each major gets its own tree.

freedomnas-core is not built as a wheel, because its `pyproject.toml` needs
setuptools 77 and FreeBSD's is older. It is installed the way every edition
installs it: the package under `<root>/core`, put on `sys.path` by a `.pth`
file in site-packages.

## Layout

```
out/FreeBSD:15:amd64/latest/All/freedomnas-<name>-<version>.pkg
out/FreeBSD:15:amd64/latest/{meta.conf,packagesite.pkg,data.pkg}
out/freedomnas.pub
```

Only `bin/` and this file are tracked. `out/` is rebuilt from them, and
`*.key` never leaves the build machine.

The root the files go under is not written in the script: it is
`paths.install_root` in freedomnas-profiles' `os/os-freebsd.json`,
`/usr/local/lib/freedomnas`. Every installed component finds the others
relative to its own location, and the configuration lives where the same
profile's `paths.config_dir` says, `/usr/local/etc/freedomnas`.

## Published repository

`.forgejo/workflows/publish-packages.yml` builds the packages on the
self-hosted runner and publishes them to Codeberg's generic registry, where
a FreeBSD machine reads them as a pkg repository:

```
https://codeberg.org/api/packages/FreedomNAS/generic/freedomnas-freebsd/<major>-<group>
```

| Run | Builds | Published as |
|-----|--------|--------------|
| `ref: dev` (also every night) | every component at `dev`, versioned `X.Y.Z.<commit stamp>` | `15-dev` |
| `ref: main` | the newest release tag, `vX.Y.Z` | `15-main` |

`ci/build-in-vm.sh` does the FreeBSD part from Linux: it boots FreeBSD's own
VM image under QEMU with freedomnas-image-builder's driver (that checkout
must sit beside this one), runs `ci/build-in-guest.sh` there —
`bin/build-freedomnas-pkgs.sh`, then `pkg repo` with the signing key — and
reads the result back from a scratch disk, with the guest's log. The
catalogue is flat, the packages beside `meta.conf` and `packagesite.pkg`,
because the registry has no directories. `bin/publish-codeberg.sh` uploads
it, replacing files with the same name, and removes the packages the new
catalogue no longer lists.

Secrets: the private signing key as `FREEBSD_SIGNING_KEY` (the PEM of
`freedomnas.key`, which stays out of git), and the organisation's
`PACKAGE_REGISTRY_USER` / `PACKAGE_REGISTRY_TOKEN`. The public key is
`keys/freedomnas.pub` (sha256 `72828ec3…f6baf32a`), the same one
freedomnas-profiles' `installer/installer-freebsd.json` writes.

## Using it

freedomnas-installer writes both files on the FreedomNAS machine: the
public key as `/usr/local/etc/ssl/freedomnas.pub`, and
`/usr/local/etc/pkg/repos/FreedomNAS.conf`:

```
FreedomNAS: {
  url: "https://codeberg.org/api/packages/FreedomNAS/generic/freedomnas-freebsd/${VERSION_MAJOR}-main",
  signature_type: "pubkey",
  pubkey: "/usr/local/etc/ssl/freedomnas.pub",
  enabled: yes
}
```

Then `pkg update && pkg install freedomnas-webui`. pkg expands
`${VERSION_MAJOR}` itself, so a machine follows its own major version. For a
local build, `url` is `file:///path/to/out/${ABI}/latest`. Verified on
FreeBSD 15.1-RELEASE: the signed flat catalogue, served over HTTP, installs
the five packages with their FreeBSD dependencies, and the core and the
WebUI import.

## License

GPL-2.0-or-later: the GNU General Public License, version 2 or (at your
option) any later version. The text of version 2 is in `LICENSE`.

The packages built from here keep the licenses of what they package —
MPL-2.0 for the FreedomNAS components.
