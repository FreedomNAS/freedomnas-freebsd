# freedomnas-freebsd

A pkg repository for FreedomNAS on FreeBSD: the four FreedomNAS packages,
built from the checkouts beside this one.

| Package | Depends on (FreeBSD's own repository) |
|---------|----------------------------------------|
| `freedomnas-profiles` | — |
| `freedomnas-core` | `python3`, `py312-pyyaml`, `py312-cryptography` |
| `freedomnas-webui` | `py312-fastapi`, `-uvicorn`, `-websockets`, `-Jinja2`, `-python-pam`, `-pyyaml` |
| `freedomnas-installer` | `python3`, `cdialog`, `curl` |

Everything else FreedomNAS installs on FreeBSD is already in FreeBSD's
repository, `sysutils/topgrade` included, or in the base system (ZFS,
bhyve, the NFS server, efibootmgr). The `py312` flavor is whatever the
`python3` metaport points at when the packages are built.

## Building

On FreeBSD, after `pkg update`, with the four FreedomNAS checkouts beside
this one and `python3` and `git` installed:

```sh
bin/build-freedomnas-pkgs.sh                    # all four
bin/build-freedomnas-pkgs.sh freedomnas-webui   # one of them
SNAPSHOT=1 bin/build-freedomnas-pkgs.sh         # ...as 1.0.<yyyymmddhhmm>
ABI=FreeBSD:14 bin/build-freedomnas-pkgs.sh     # for another major version
bin/make-repo.sh --new-key freedomnas.key       # once: the signing key pair
SIGNING_KEY=freedomnas.key bin/make-repo.sh     # the signed catalogue
```

The version is the upstream half of each component's `debian/changelog`,
the same number freedomnas-deb publishes. Nothing is compiled: each package
is a staging directory handed to `pkg create`. The packages are
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

## Using it

On the FreedomNAS machine, with the public key in
`/usr/local/etc/ssl/freedomnas.pub`:

```sh
mkdir -p /usr/local/etc/pkg/repos
cat > /usr/local/etc/pkg/repos/FreedomNAS.conf <<'EOF'
FreedomNAS: {
  url: "file:///path/to/out/${ABI}/latest",
  signature_type: "pubkey",
  pubkey: "/usr/local/etc/ssl/freedomnas.pub",
  enabled: yes
}
EOF
pkg update && pkg install freedomnas-webui
```

A hosted copy only changes the `url`. Verified on FreeBSD 15.1-RELEASE:
the signed catalogue installs all four packages together with their 36
dependencies from FreeBSD's repository, the WebUI starts from
`supervisor.sh` and serves `/setup/`, and `pkg delete` leaves nothing
behind.

## License

GPL-2.0-or-later: the GNU General Public License, version 2 or (at your
option) any later version. The text of version 2 is in `LICENSE`.

The packages built from here keep the licenses of what they package —
MPL-2.0 for the FreedomNAS components.
