# perses

[Perses](https://perses.dev) dashboards, with the datasource and static list
variables and the time series and Markdown panels; its other plugins are
[`perses-plugin-*`](../perses-plugins) packages. `apk add perses`, once the
[feed](../README.md#adding-the-feed) is added.

## Configuration

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

An `env` entry for a variable the options set, by name or by index, is
refused.

## Login

Each OpenID Connect provider is an `oidc` section (`slug_id`, `name`,
`issuer`, `client_id`, `client_secret_file`, `list scope`, default `openid
profile email`, and `disable_pkce`); its callback is
`<public URL>/api/auth/providers/oidc/<slug_id>/callback`.

## Datasources on loopback

Perses proxies every query, and denies destinations on loopback and
link-local: a datasource on `127.0.0.1`, such as victoria-metrics with its
default `listen`, needs `datasource_allow '127.0.0.0/8'`. That lets whoever
may edit datasources reach every service on loopback through Perses, LuCI
included, so turn `auth` on with it.

## Plugins

Its panels, queries and variables are plugins. Perses accepts no dashboard
without at least one variable plugin and one panel plugin, so the package
comes with four; the others are [`perses-plugin-*`](../perses-plugins)
packages.

## Provisioning

Dashboards, projects and datasources can be files: JSON or YAML resources
in a `provisioning` folder, loaded at start and every
`provisioning_interval`. A file overwrites what the UI changed in its
resource; removing a file does not remove the resource, which is deleted in
the UI or through the API.

## Secrets and jail

Its jail sees `/etc/perses` read-only, with its encryption key and any
secret files (`client_secret_file`); make those readable to its group:
`chgrp perses secret && chmod 640 secret`. `/etc/perses` is kept across a
sysupgrade: a lost key makes the datasource secrets in its database
unreadable. A provisioning folder elsewhere is mounted in its jail.
