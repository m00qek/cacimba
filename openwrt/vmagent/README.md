# vmagent

[VictoriaMetrics agent](https://docs.victoriametrics.com/victoriametrics/vmagent/):
scrapes Prometheus metrics and remote-writes them, queuing on disk per
target. `apk add vmagent`, once the [feed](../README.md#adding-the-feed) is
added.

## Configuration

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

`ubus call service validate` reports invalid options; `extra_args` entries
cannot contain spaces. A changed scrape configuration restarts it on
`service vmagent reload`.

## Storage

`/var` is RAM on OpenWrt: to keep the queue across reboots, point `data_dir`
at persistent storage and raise `max_disk_per_url` with it. When `data_dir`
is under a mount point declared in `/etc/config/fstab`, vmagent waits for
that mount and starts when it appears, rather than queuing onto the overlay.

## Jail

It runs in a ujail as the `vmagent` user, which owns `data_dir`, and gets 30
seconds to flush its buffers when stopped. The jail holds only its scrape
configuration, `data_dir`, the CA bundle, `/etc/hosts` and the resolver
files: a file the scrape configuration refers to, such as a `ca_file`, needs
a `jail_mount` entry.
