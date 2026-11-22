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
| [vmagent](openwrt/vmagent) | [VictoriaMetrics agent](https://docs.victoriametrics.com/victoriametrics/vmagent/): scrapes Prometheus metrics and remote-writes them, queuing on disk per target | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.156.0-r4 |
| [victoria-metrics](openwrt/victoria-metrics) | [VictoriaMetrics](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/) single-node time series database: Prometheus remote-write in, PromQL/MetricsQL out | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.156.0-r3 |
| [victoria-logs](openwrt/victoria-logs) | [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) single-node log database: syslog, Loki, Elasticsearch and JSON-lines in, LogsQL out | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.54.0-r3 |
| [tinyauth](openwrt/tinyauth) | [Tinyauth](https://tinyauth.app): a login page (local users, OAuth/OIDC, LDAP) in front of web apps, for a reverse proxy's forward auth | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 5.2.0-r1 |
| [perses](openwrt/perses) | [Perses](https://perses.dev) dashboards, with the datasource and static list variables and the time series and Markdown panels | `x86_64`, `aarch64_generic` | 0.55.1-r2 |
| [perses-plugin-*](openwrt/perses-plugins) | Its other plugins, one package each: `prometheus`, `victorialogs`, `statchart`, `gaugechart`, `barchart`, `piechart`, `table`, `timeseriestable`, `logstable`, `statushistorychart`, `heatmapchart`, `histogramchart`, `logexplorer` | `noarch` | upstream's, with perses 0.55.1 |

### Adding the feed

```sh
wget -O /etc/apk/keys/cacimba.pem \
  https://m00qek.github.io/cacimba/openwrt/25.12/feed.pub.pem
. /etc/openwrt_release
echo "https://m00qek.github.io/cacimba/openwrt/25.12/$DISTRIB_ARCH/packages.adb" \
  >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add vmagent
```

The packages and indexes are signed; the key above is the one in
[`apk.pub`](apk.pub). To build it into an image, put it in the image's
`/etc/apk/keys/` (ImageBuilder `FILES=`).

Upgrading a package restarts its service if it is running, so the
version installed is the version running.

The feed keeps the three newest versions of each package, so the two before
the current one can be installed by their URLs to roll back (perses, at
~26MB a version, keeps two). The index lists the newest only.

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

### victoria-metrics and victoria-logs

Both are configured in their `/etc/config/<name>`, and neither starts until
`data_dir` is set: a database needs storage that survives a reboot, and only
you know where that is (a USB disk, an SD card; flash wears out under a
database's writes). A `data_dir` in RAM (`/tmp`, `/var`) starts, with a
warning in the log.

```sh
uci set victoria-metrics.main.data_dir=/mnt/data/victoria-metrics
uci commit victoria-metrics
service victoria-metrics start
```

| Option | victoria-metrics | victoria-logs | Flag |
|--------|------------------|---------------|------|
| `enabled` | `1` | `1` | |
| `data_dir` | none: required | none: required | `-storageDataPath` |
| `retention` | `30d` | `7d` | `-retentionPeriod` |
| `listen` | `127.0.0.1:8428` | `127.0.0.1:9428` | `-httpListenAddr` |
| `memory_allowed` | `64MB` | `64MB` | `-memory.allowedBytes` |
| `gomemlimit` | `128MiB` | `128MiB` | `GOMEMLIMIT` |
| `log_level` | `INFO` | `INFO` | `-loggerLevel` |
| `extra_args`, `jail_mount`, `jail_mount_rw` (lists) | none | none | as for vmagent |

Neither has authentication of its own, so both listen on loopback by
default. Like vmagent, each runs in a ujail as its own user, which owns
`data_dir`, waits for `data_dir`'s mount when it is declared in
`/etc/config/fstab`, and gets 60 seconds to flush to disk when stopped.

victoria-logs takes syslog in through `syslog` sections, one per input. The
tenant is the `AccountID:ProjectID` the input's logs are stored under:

```
config syslog
	option proto 'tcp'              # or udp
	option listen '127.0.0.1:1514'
	option tenant '0:0'
```

It runs unprivileged, so a syslog port must be 1024 or above.

### tinyauth

Configured in `/etc/config/tinyauth`, like every package here. Tinyauth reads
its settings from `TINYAUTH_*` environment variables, so the service turns
its options into them, and takes any other tinyauth setting as an `env`
entry. (Tinyauth also reads a YAML file, but only instead of the
environment, never with it.) It does not start without an `app_url`.

```sh
uci set tinyauth.main.app_url=https://auth.example.com
uci add_list tinyauth.main.env='TINYAUTH_OAUTH_PROVIDERS_POCKETID_NAME=Pocket ID'
uci add_list tinyauth.main.env=TINYAUTH_OAUTH_PROVIDERS_POCKETID_CLIENTSECRETFILE=/etc/tinyauth/pocketid-secret
uci commit tinyauth
service tinyauth start
```

| Option | Default | Variable |
|--------|---------|----------|
| `enabled` | `1` | |
| `app_url` | none: required, a domain | `TINYAUTH_APPURL` |
| `address` | `127.0.0.1` | `TINYAUTH_SERVER_ADDRESS` |
| `port` | `3000` | `TINYAUTH_SERVER_PORT` |
| `data_dir` | `/var/lib/tinyauth` | its database, OIDC keys and resources |
| `log_level` | `info` | `TINYAUTH_LOG_LEVEL` |
| `analytics` | `0` | `TINYAUTH_ANALYTICS_ENABLED` |
| `gomemlimit` | `64MiB` | `GOMEMLIMIT` |
| `env` (list) | none | any other `TINYAUTH_*` setting, `NAME=value`; values may contain spaces |
| `jail_mount`, `jail_mount_rw` (lists) | none | more paths in its jail |

An `env` entry for a variable an option sets is refused, rather than one
silently winning. Upstream listens on every address and reports its version
home; here it listens on loopback, behind the reverse proxy, with analytics
off. `data_dir` in RAM only signs everyone out on a reboot, so it has a
default; use persistent storage if tinyauth is itself an OIDC provider, whose
keys must not change.

Its jail sees `/etc/tinyauth` read-only: keep secrets there as files and
point the `*FILE` settings at them (`..._CLIENTSECRETFILE`,
`TINYAUTH_AUTH_USERSFILE`, ...). It runs as the `tinyauth` user, so make them
readable to it: `chgrp tinyauth secret && chmod 640 secret`.

### perses

Configured in `/etc/config/perses`. Perses reads every setting of its YAML
configuration from a `PERSES_*` environment variable too, so the service
turns its options into them, and takes any other setting as an `env` entry.
It does not start until `data_dir` is set: its database and its unpacked
plugins go there.

```sh
uci set perses.main.data_dir=/mnt/data/perses
uci commit perses
apk add perses-plugin-prometheus      # restarts perses
service perses start
```

| Option | Default | Variable or flag |
|--------|---------|------------------|
| `enabled` | `1` | |
| `data_dir` | none: required | `<data_dir>/db` its database, `<data_dir>/plugins` its plugins |
| `listen` | `127.0.0.1:8080` | `-web.listen-address` |
| `log_level` | `info` | `-log.level` |
| `gomemlimit` | `256MiB` | `GOMEMLIMIT` |
| `encryption_key_file` | `/etc/perses/encryption-key`, made on the first start | `PERSES_SECURITY_ENCRYPTION_KEY_FILE` |
| `auth` | `0` | `PERSES_SECURITY_ENABLE_AUTH`, and its own authorization |
| `native_login` | `1` | `PERSES_SECURITY_AUTHENTICATION_PROVIDERS_ENABLE_NATIVE` |
| `guest_action`, `guest_scope` (lists) | none, `*` | one guest permission: what a user without a role may do |
| `explorer` | `0` | `PERSES_FRONTEND_EXPLORER_ENABLE` |
| `provisioning` (list) | `/etc/perses/provisioning` | `PERSES_PROVISIONING_FOLDERS_<n>` |
| `provisioning_interval` | `1h` | `PERSES_PROVISIONING_INTERVAL` |
| `datasource_allow` (list) | none | `PERSES_DATASOURCE_PROXY_ALLOWED_NETWORKS_<n>`: networks datasources may point at besides the default ones |
| `env` (list) | none | any other `PERSES_*` setting, `NAME=value` |
| `jail_mount`, `jail_mount_rw` (lists) | none | more paths in its jail |

Each OpenID Connect provider is an `oidc` section (`slug_id`, `name`,
`issuer`, `client_id`, `client_secret_file`, `list scope`, default `openid
profile email`, and `disable_pkce`); its callback is
`<public URL>/api/auth/providers/oidc/<slug_id>/callback`. An `env` entry
for a variable the options set, by name or by index, is refused.

Perses proxies every query, and denies destinations on loopback and
link-local: a datasource on `127.0.0.1`, such as victoria-metrics with its
default `listen`, needs `datasource_allow '127.0.0.0/8'`. That lets whoever
may edit datasources reach every service on loopback through Perses, LuCI
included, so turn `auth` on with it.

Its panels, queries and variables are plugins. Perses accepts no dashboard
without at least one variable plugin and one panel plugin, so the package
comes with four; the others are `perses-plugin-*` packages, each ~3.6MB, and
~11MB once Perses unpacks it into `data_dir` on its next start. Installing
or removing one restarts it.

Dashboards, projects and datasources can be files: JSON or YAML resources
in a `provisioning` folder, loaded at start and every
`provisioning_interval`. A file overwrites what the UI changed in its
resource; removing a file does not remove the resource, which is deleted in
the UI or through the API.

Its jail sees `/etc/perses` read-only, with its encryption key and any
secret files (`client_secret_file`); make those readable to its group:
`chgrp perses secret && chmod 640 secret`. `/etc/perses` is kept across a
sysupgrade: a lost key makes the datasource secrets in its database
unreadable. A provisioning folder elsewhere is mounted in its jail.

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

Every package is configured through UCI, `/etc/config/<name>`: its init
script turns the options into the program's flags, environment or own
configuration file at start, so there is one place to configure it, and
tools that manage UCI manage it too.

1. `openwrt/<name>/Makefile`: `PKG_SOURCE_URL` and `PKG_HASH` per CPU,
   copied from upstream's checksums, the install rules, and the `postinst`
   that restarts the service on upgrade.
2. `openwrt/<name>/files/`: its procd init script (validated options, its
   own user, a ujail) and its UCI defaults, listed in `conffiles`.
3. `openwrt/<name>/test.sh`: what can be checked without procd.
4. An entry in `feed.json`, and a row above.

The publish signs with the repository secret `APK_FEED_SIGNING_KEY`, the
private half of `apk.pub`, an EC P-256 key:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out apk.key
openssl ec -in apk.key -pubout -out apk.pub     # committed
gh secret set APK_FEED_SIGNING_KEY < apk.key && shred -u apk.key
```
