# cacimba

Upstream software, packaged to run as proper services.

A cacimba is a well dug by hand in a dry riverbed: you draw from it what the
river brings. This repository takes the release builds upstream projects
already publish and wraps each one as a package for an operating system:
an init script, a default configuration, and the binary where the system
expects it.

Only recipes live here. Each one names the upstream download and its hash;
CI fetches it, checks the hash, packages it, and publishes the result.

| Directory | What |
|-----------|------|
| [`openwrt/`](openwrt) | an OpenWrt 25.12 (apk) package feed |

## OpenWrt

### Packages

| Package | Description | Architectures | Version |
|---------|-------------|---------------|---------|
| [vmagent](openwrt/vmagent) | [VictoriaMetrics agent](https://docs.victoriametrics.com/victoriametrics/vmagent/): scrapes Prometheus metrics and remote-writes them, queuing on disk per target | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.156.0-r1 |

### Adding the feed

```sh
wget -O /etc/apk/keys/cacimba.pem \
  https://m00qek.github.io/cacimba/openwrt/25.12/feed.pub.pem
echo https://m00qek.github.io/cacimba/openwrt/25.12/packages.adb \
  >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add vmagent
```

The packages and indexes are signed; the key above is the one in
[`apk.pub`](apk.pub). To build it into an image, put it in the image's
`/etc/apk/keys/` (ImageBuilder `FILES=`).

The feed keeps the two newest versions of each package, so the previous one
can be installed by its URL to roll back. The index lists the newest only.

### vmagent

Configured in `/etc/config/vmagent`; what to scrape is a Prometheus scrape
configuration, `/etc/vmagent/scrape.yml` by default. It does not start until
there is somewhere to write:

```sh
uci add_list vmagent.main.remote_write='http://127.0.0.1:8428/api/v1/write'
uci add_list vmagent.main.label='site=home'
uci commit vmagent
reload_config               # or: service vmagent reload
```

| Option | Default | Flag |
|--------|---------|------|
| `enabled` | `1` | |
| `config` | `/etc/vmagent/scrape.yml` | `-promscrape.config` |
| `remote_write` (list) | none: required | `-remoteWrite.url` |
| `label` (list) | none | `-remoteWrite.label` |
| `data_dir` | `/var/lib/vmagent` | `-remoteWrite.tmpDataPath` |
| `max_disk_per_url` | `16MB` | `-remoteWrite.maxDiskUsagePerURL` |
| `listen` | `127.0.0.1:8429` | `-httpListenAddr` |
| `memory_allowed` | `32MB` | `-memory.allowedBytes` |
| `gomemlimit` | `64MiB` | `GOMEMLIMIT` |
| `log_level` | `INFO` | `-loggerLevel` (`INFO`, `WARN`, `ERROR`) |
| `extra_args` (list) | none | any other flag, one per entry |
| `jail_mount`, `jail_mount_rw` (lists) | none | more paths in its jail |

The memory defaults are absolute on purpose: vmagent's own default lets its
caches take 60% of RAM, and a router has no swap. An unreachable target
logs an error on every scrape into logd's small buffer;
`-promscrape.suppressScrapeErrors` in `extra_args` silences those alone.

`/var` is RAM on OpenWrt: to keep the queue across reboots, point `data_dir`
at persistent storage and raise `max_disk_per_url` with it. When `data_dir`
is under a mount point declared in `/etc/config/fstab`, vmagent waits for
that mount and starts when it appears, rather than queuing onto the overlay.

It runs in a ujail as the `vmagent` user, which owns `data_dir`, and gets 30
seconds to flush its buffers when stopped. The jail holds only its scrape
configuration, `data_dir`, the CA bundle, `/etc/hosts` and the resolver
files: a file the scrape configuration refers to, such as a `ca_file`, needs
a `jail_mount` entry. A changed scrape configuration restarts it on
`service vmagent reload`. `ubus call service validate` reports invalid
options; `extra_args` entries cannot contain spaces.

## How the feed is built

[`feed.json`](feed.json) lists the OpenWrt releases, their architectures,
and each package with how it is built:

- `"build": "prebuilt"`: an upstream binary, built for each of the package's
  `"arches"`. The Makefile picks the upstream download for the SDK's CPU.
- `"build": "noarch"`: nothing architecture-specific, built once.

[`.github/workflows/feed.yml`](.github/workflows/feed.yml) builds every
changed package in the OpenWrt SDK
([`scripts/build.sh`](scripts/build.sh)), installs the x86_64 and noarch
builds in an OpenWrt rootfs container and runs the package's `test.sh`
([`scripts/test.sh`](scripts/test.sh)), and, on `main`, signs, files and
indexes them on the `gh-pages` branch
([`scripts/publish.sh`](scripts/publish.sh)). `gh-pages` is a single commit,
replaced on every publish, so old binaries do not pile up in its history.

To build and test a package locally, with docker:

```sh
sh scripts/build.sh 25.12 openwrt/sdk:x86-64-25.12.6 x86_64 out vmagent
sh scripts/test.sh openwrt/rootfs:x86_64-25.12.6 out vmagent
```

### Adding a package

1. `openwrt/<name>/Makefile`: `PKG_SOURCE_URL` and `PKG_HASH` per CPU,
   copied from upstream's checksums, and the install rules.
2. `openwrt/<name>/files/`: its procd init script, UCI defaults, and any
   default configuration, listed in `conffiles`.
3. `openwrt/<name>/test.sh`: what can be checked without procd.
4. An entry in `feed.json`, and a row above.

The publish signs with the repository secret `APK_FEED_SIGNING_KEY`, the
private half of `apk.pub`, an EC P-256 key:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out apk.key
openssl ec -in apk.key -pubout -out apk.pub     # committed
gh secret set APK_FEED_SIGNING_KEY < apk.key && shred -u apk.key
```
