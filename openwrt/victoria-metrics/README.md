# victoria-metrics

[VictoriaMetrics](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/)
single-node time series database: Prometheus remote-write in,
PromQL/MetricsQL out. `apk add victoria-metrics`, once the
[feed](../README.md#adding-the-feed) is added.

## Configuration

Configured in `/etc/config/victoria-metrics`. It does not start until
`data_dir` is set: a database needs storage that survives a reboot, and only
you know where that is (a USB disk, an SD card; flash wears out under a
database's writes). A `data_dir` in RAM (`/tmp`, `/var`) starts, with a
warning in the log.

```sh
uci set victoria-metrics.main.data_dir=/mnt/data/victoria-metrics
uci commit victoria-metrics
service victoria-metrics start
```

| Option | Default | Flag |
|--------|---------|------|
| `enabled` | `1` | |
| `data_dir` | none: required | `-storageDataPath` |
| `retention` | `30d` | `-retentionPeriod` |
| `listen` | `127.0.0.1:8428` | `-httpListenAddr` |
| `memory_allowed` | `64MB` | `-memory.allowedBytes` |
| `gomemlimit` | `128MiB` | `GOMEMLIMIT` |
| `log_level` | `INFO` | `-loggerLevel` |
| `extra_args` (list) | none | any other flag, one per entry; no spaces |
| `jail_mount`, `jail_mount_rw` (lists) | none | more paths in its jail |

It has no authentication of its own, so it listens on loopback by default.

## Storage and jail

When `data_dir` is under a mount point declared in `/etc/config/fstab`, it
waits for that mount and starts when it appears. It runs in a ujail as the
`victoria-metrics` user, which owns `data_dir`, and gets 60 seconds to flush
to disk when stopped.
