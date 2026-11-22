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
| [`openwrt/`](openwrt) | an OpenWrt 25.12 (apk) package feed: adding it, upgrades, how it is built |

## Packages

| Package | Description | Architectures | Version |
|---------|-------------|---------------|---------|
| [vmagent](openwrt/vmagent) | [VictoriaMetrics agent](https://docs.victoriametrics.com/victoriametrics/vmagent/): scrapes Prometheus metrics and remote-writes them, queuing on disk per target | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.156.0-r4 |
| [victoria-metrics](openwrt/victoria-metrics) | [VictoriaMetrics](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/) single-node time series database: Prometheus remote-write in, PromQL/MetricsQL out | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.156.0-r3 |
| [victoria-logs](openwrt/victoria-logs) | [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) single-node log database: syslog, Loki, Elasticsearch and JSON-lines in, LogsQL out | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 1.54.0-r3 |
| [tinyauth](openwrt/tinyauth) | [Tinyauth](https://tinyauth.app): a login page (local users, OAuth/OIDC, LDAP) in front of web apps, for a reverse proxy's forward auth | `x86_64`, `aarch64_generic`, `aarch64_cortex-a53` | 5.2.0-r1 |
| [perses](openwrt/perses) | [Perses](https://perses.dev) dashboards, with the datasource and static list variables and the time series and Markdown panels | `x86_64`, `aarch64_generic` | 0.55.1-r2 |
| [perses-plugin-*](openwrt/perses-plugins) | Perses' other plugins, one package each: datasources for Prometheus/VictoriaMetrics and VictoriaLogs, eleven more panels, and the logs explorer | `noarch` | upstream's, with perses 0.55.1 |

How to add the feed, upgrade, roll back and build: [`openwrt/`](openwrt).
Each package's configuration: its own README, linked above.
