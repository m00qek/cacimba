#!/bin/sh
# Smoke test, run by scripts/test.sh in a privileged OpenWrt rootfs with the
# package installed. There is no procd there: the init script's start_service
# runs with procd's calls replaced by ones that print them, and tinyauth then
# runs in ujail as procd would start it, to check it comes up there.
set -eu

fail() { echo "tinyauth test: $*" >&2; exit 1; }

/usr/bin/tinyauth version 2>&1 | grep -q 'v5\.' || fail "tinyauth version"
/etc/init.d/tinyauth enabled || fail "the service is not enabled on install"
grep -q '^tinyauth:' /etc/passwd || fail "no tinyauth user"
[ -d /etc/tinyauth ] || fail "no /etc/tinyauth for secret files"
[ "$(uci -q get tinyauth.main.address)" = 127.0.0.1 ] || fail "default config does not listen on loopback"

# start: run the init script's start_service, printing what it asks of procd.
start() {
	sh -c '
		initscript=/etc/init.d/tinyauth
		. /lib/functions.sh
		. /lib/functions/procd.sh
		procd_open_instance() { :; }
		procd_close_instance() { :; }
		procd_set_param() { echo "set $*"; }
		procd_append_param() { echo "append $*"; }
		procd_add_jail() { echo "jail $*"; }
		procd_add_jail_mount() { for a; do echo "mount $a"; done; }
		procd_add_jail_mount_rw() { for a; do echo "mount_rw $a"; done; }
		. /etc/init.d/tinyauth
		start_service
	' 2>&1
}

out=$(start) && fail "started without an app_url"
echo "$out" | grep -q "no app_url" || fail "no app_url: $out"

# A provider whose client secret is a file in /etc/tinyauth, readable by the
# tinyauth group only, as the README says to keep it.
printf 'not-a-real-secret' > /etc/tinyauth/test-client-secret
chgrp tinyauth /etc/tinyauth/test-client-secret
chmod 640 /etc/tinyauth/test-client-secret
uci set tinyauth.main.app_url=https://auth.example.com
uci set tinyauth.main.data_dir=/srv/tinyauth
uci add_list tinyauth.main.env='TINYAUTH_UI_TITLE=My test network'
uci add_list tinyauth.main.env='TINYAUTH_OAUTH_PROVIDERS_TEST_NAME=Test ID'
uci add_list tinyauth.main.env=TINYAUTH_OAUTH_PROVIDERS_TEST_CLIENTID=test-client
uci add_list tinyauth.main.env=TINYAUTH_OAUTH_PROVIDERS_TEST_CLIENTSECRETFILE=/etc/tinyauth/test-client-secret
uci add_list tinyauth.main.env='TINYAUTH_OAUTH_PROVIDERS_TEST_SCOPES=openid email'
uci add_list tinyauth.main.env=TINYAUTH_OAUTH_PROVIDERS_TEST_AUTHURL=https://id.example.com/authorize
uci add_list tinyauth.main.env=TINYAUTH_OAUTH_PROVIDERS_TEST_TOKENURL=https://id.example.com/token
uci add_list tinyauth.main.env=TINYAUTH_OAUTH_PROVIDERS_TEST_USERINFOURL=https://id.example.com/userinfo
uci commit tinyauth
mkdir -p /srv/tinyauth
touch /srv/tinyauth/before
out=$(start) || fail "did not start: $out"
for want in \
	"set command /usr/bin/tinyauth" \
	"set env TINYAUTH_APPURL=https://auth.example.com TINYAUTH_SERVER_ADDRESS=127.0.0.1 TINYAUTH_SERVER_PORT=3000 TINYAUTH_DATABASE_PATH=/srv/tinyauth/tinyauth.db TINYAUTH_RESOURCES_PATH=/srv/tinyauth/resources TINYAUTH_OIDC_PRIVATEKEYPATH=/srv/tinyauth/tinyauth_oidc_key TINYAUTH_OIDC_PUBLICKEYPATH=/srv/tinyauth/tinyauth_oidc_key.pub TINYAUTH_LOG_LEVEL=info TINYAUTH_ANALYTICS_ENABLED=false TINYAUTH_LABELPROVIDER=none NO_COLOR=1" \
	"append env GOMEMLIMIT=64MiB" \
	"append env TINYAUTH_UI_TITLE=My test network" \
	"append env TINYAUTH_OAUTH_PROVIDERS_TEST_SCOPES=openid email" \
	"jail tinyauth log procfs requirejail" \
	"mount /etc/tinyauth" \
	"mount /etc/ssl/certs" \
	"mount_rw /srv/tinyauth" \
	"set user tinyauth" \
	"set no_new_privs 1"; do
	echo "$out" | grep -qxF "$want" || fail "missing \"$want\" in:
$out"
done
[ "$(ls -ld /srv/tinyauth | awk '{print $3}')" = tinyauth ] || fail "data_dir not owned by tinyauth"
[ "$(ls -l /srv/tinyauth/before | awk '{print $3}')" = tinyauth ] || fail "data_dir contents not handed over"
touch /srv/tinyauth/after
start >/dev/null
[ "$(ls -l /srv/tinyauth/after | awk '{print $3}')" = root ] || fail "re-owned data_dir on a later start"

# The jail it asked for is enough to run in, with this environment: its
# state lands in data_dir, and it reads the secret file.
pidof ubusd >/dev/null || { ubusd & sleep 1; }
jail="-n tinyauth -E -c -p -U tinyauth -G tinyauth"
for m in $(echo "$out" | sed -n 's/^mount //p'); do jail="$jail -r $m"; done
for m in $(echo "$out" | sed -n 's/^mount_rw //p'); do jail="$jail -w $m"; done
# Every variable it was given, values with spaces included, one per line.
envs=$(echo "$out" | sed -n 's/^append env //p'
	echo "$out" | sed -n 's/^set env //p' | tr ' ' '\n')
names=
while IFS= read -r e; do
	[ -n "$e" ] || continue
	export "$e"
	names="$names ${e%%=*}"
done <<EOF
$envs
EOF
for v in $names; do jail="$jail -e $v"; done
# shellcheck disable=SC2086  # word-split on purpose: options
/sbin/ujail $jail -- /usr/bin/tinyauth > /tmp/tinyauth.log 2>&1 &
pid=$!
health=
for _ in 1 2 3 4 5 6 7 8 9 10; do
	sleep 1
	health=$(wget -qO- http://127.0.0.1:3000/api/healthz 2>/dev/null) && break
	health=$(wget -qO- http://127.0.0.1:3000/healthz 2>/dev/null) && break
done
kill "$pid" 2>/dev/null || true
[ -n "$health" ] || fail "tinyauth did not come up in its jail:
$(cat /tmp/tinyauth.log)"
[ -f /srv/tinyauth/tinyauth.db ] || fail "no database in data_dir:
$(ls -la /srv/tinyauth)"
if grep -qi "permission denied\|no such file" /tmp/tinyauth.log; then
	fail "it could not read a file it was given:
$(cat /tmp/tinyauth.log)"
fi

# An env entry for a variable an option sets is refused, and so is one that
# is not a TINYAUTH_ setting.
uci add_list tinyauth.main.env=TINYAUTH_SERVER_PORT=4000
uci commit tinyauth
out=$(start) && fail "started with an env entry for TINYAUTH_SERVER_PORT"
echo "$out" | grep -q "set from an option" || fail "owned env entry not reported: $out"
uci del_list tinyauth.main.env=TINYAUTH_SERVER_PORT=4000
uci add_list tinyauth.main.env=PATH=/tmp
uci commit tinyauth
out=$(start) && fail "started with an env entry PATH"
echo "$out" | grep -q "is not TINYAUTH_" || fail "foreign env entry not reported: $out"
uci del_list tinyauth.main.env=PATH=/tmp
uci commit tinyauth

# An invalid option stops it.
uci set tinyauth.main.port=99999
uci commit tinyauth
out=$(start) && fail "started with port=99999"
echo "$out" | grep -q "invalid configuration" || fail "invalid config not reported: $out"

echo "tinyauth: ok"
