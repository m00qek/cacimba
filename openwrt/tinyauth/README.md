# tinyauth

[Tinyauth](https://tinyauth.app): a login page (local users, OAuth/OIDC,
LDAP) in front of web apps, for a reverse proxy's forward auth.
`apk add tinyauth`, once the [feed](../README.md#adding-the-feed) is added.

## Configuration

Configured in `/etc/config/tinyauth`. Tinyauth reads its settings from
`TINYAUTH_*` environment variables, so the service turns its options into
them, and takes any other tinyauth setting as an `env` entry. (Tinyauth also
reads a YAML file, but only instead of the environment, never with it.) It
does not start without an `app_url`.

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
off.

## Storage

`data_dir` in RAM only signs everyone out on a reboot, so it has a default;
use persistent storage if tinyauth is itself an OIDC provider, whose keys
must not change.

## Secrets and jail

Its jail sees `/etc/tinyauth` read-only: keep secrets there as files and
point the `*FILE` settings at them (`..._CLIENTSECRETFILE`,
`TINYAUTH_AUTH_USERSFILE`, ...). It runs as the `tinyauth` user, so make them
readable to it: `chgrp tinyauth secret && chmod 640 secret`.
