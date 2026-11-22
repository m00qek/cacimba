#!/bin/sh
# Smoke test, run by scripts/test.sh in a privileged OpenWrt rootfs with the
# package installed. There is no procd there: the init script's start_service
# runs with procd's calls replaced by ones that print them, and perses then
# runs in ujail as procd would start it, to check it comes up there, loads
# its plugins and provisions a dashboard.
set -eu

fail() { echo "perses test: $*" >&2; exit 1; }

/usr/bin/perses -h 2>&1 | grep -q -- '-web.listen-address' || fail "perses -h"
/etc/init.d/perses enabled || fail "the service is not enabled on install"
grep -q '^perses:' /etc/passwd || fail "no perses user"
[ -d /etc/perses/provisioning ] || fail "no /etc/perses/provisioning"
grep -qx /etc/perses/ /lib/upgrade/keep.d/perses || fail "/etc/perses is not kept across a sysupgrade"
[ "$(ls /usr/share/perses/plugins-archive | wc -l)" = 4 ] ||
	fail "not the four builtin plugins: $(ls /usr/share/perses/plugins-archive)"
[ "$(uci -q get perses.main.listen)" = 127.0.0.1:8080 ] || fail "default config does not listen on loopback"

# start: run the init script's start_service, printing what it asks of procd.
start() {
	sh -c '
		initscript=/etc/init.d/perses
		. /lib/functions.sh
		. /lib/functions/procd.sh
		procd_open_instance() { :; }
		procd_close_instance() { :; }
		procd_set_param() {
			if [ "$1" = env ]; then shift; for a; do echo "env $a"; done
			else echo "set $*"; fi
		}
		procd_append_param() { shift; for a; do echo "env $a"; done; }
		procd_add_jail() { echo "jail $*"; }
		procd_add_jail_mount() { for a; do echo "mount $a"; done; }
		procd_add_jail_mount_rw() { for a; do echo "mount_rw $a"; done; }
		. /etc/init.d/perses
		start_service
	' 2>&1
}
want() {
	for w; do
		echo "$out" | grep -qxF "$w" || fail "missing \"$w\" in:
$out"
	done
}

out=$(start) && fail "started without a data_dir"
echo "$out" | grep -q "no data_dir" || fail "no data_dir: $out"

# A project and a dashboard to provision.
cat > /etc/perses/provisioning/10-project.json <<'EOF'
{"kind":"Project","metadata":{"name":"test"},"spec":{}}
EOF
cat > /etc/perses/provisioning/20-dashboard.json <<'EOF'
{"kind":"Dashboard","metadata":{"name":"home","project":"test"},"spec":{"display":{"name":"Home"},"duration":"1h","panels":{"note":{"kind":"Panel","spec":{"display":{"name":"Note"},"plugin":{"kind":"Markdown","spec":{"text":"hello"}}}}},"layouts":[]}}
EOF

uci set perses.main.data_dir=/srv/perses
uci set perses.main.provisioning_interval=5s
uci add_list perses.main.env='PERSES_SECURITY_COOKIE_SECURE=true'
uci commit perses
mkdir -p /srv/perses
touch /srv/perses/before
out=$(start) || fail "did not start: $out"
want \
	"set command /usr/bin/perses -web.listen-address=127.0.0.1:8080 -log.level=info" \
	"env PERSES_DATABASE_FILE_FOLDER=/srv/perses/db" \
	"env PERSES_PLUGIN_PATH=/srv/perses/plugins" \
	"env PERSES_PLUGIN_ARCHIVE_PATHS_0=/usr/share/perses/plugins-archive" \
	"env PERSES_SECURITY_ENCRYPTION_KEY_FILE=/etc/perses/encryption-key" \
	"env PERSES_SECURITY_ENABLE_AUTH=false" \
	"env PERSES_PROVISIONING_FOLDERS_0=/etc/perses/provisioning" \
	"env PERSES_PROVISIONING_INTERVAL=5s" \
	"env GOMEMLIMIT=256MiB" \
	"env PERSES_SECURITY_COOKIE_SECURE=true" \
	"jail perses log procfs requirejail" \
	"mount /etc/perses" \
	"mount /usr/share/perses/plugins-archive" \
	"mount_rw /srv/perses" \
	"set user perses" \
	"set no_new_privs 1"
[ "$(ls -l /srv/perses/before | awk '{print $3}')" = perses ] || fail "data_dir not handed over"
key=/etc/perses/encryption-key
[ "$(wc -c < $key)" = 32 ] || fail "the encryption key is not 32 characters: $(wc -c < $key)"
[ "$(ls -l $key | awk '{print $1, $4}')" = "-rw-r----- perses" ] || fail "key not 0640 group perses: $(ls -l $key)"
cp $key /tmp/key.before
start >/dev/null
cmp -s $key /tmp/key.before || fail "the encryption key was replaced on a later start"

# run_jailed: perses in the jail and with the environment it was given.
run_jailed() {
	pidof ubusd >/dev/null || { ubusd & sleep 1; }
	jail="-n perses -E -c -p -U perses -G perses"
	for m in $(echo "$out" | sed -n 's/^mount //p'); do jail="$jail -r $m"; done
	for m in $(echo "$out" | sed -n 's/^mount_rw //p'); do jail="$jail -w $m"; done
	names=
	while IFS= read -r e; do
		[ -n "$e" ] || continue
		export "$e"
		names="$names ${e%%=*}"
	done <<EOF
$(echo "$out" | sed -n 's/^env //p')
EOF
	for v in $names; do jail="$jail -e $v"; done
	cmd=$(echo "$out" | sed -n 's/^set command //p')
	# shellcheck disable=SC2086  # word-split on purpose: options
	/sbin/ujail $jail -- $cmd > /tmp/perses.log 2>&1 &
	pid=$!
}

run_jailed
dash=
n=0
while [ $n -lt 90 ]; do
	sleep 1
	n=$((n + 1))
	dash=$(wget -qO- http://127.0.0.1:8080/api/v1/projects/test/dashboards/home 2>/dev/null) && break
done
kill "$pid" 2>/dev/null || true
echo "$dash" | grep -q '"Markdown"' || fail "no provisioned dashboard in its jail:
$(cat /tmp/perses.log)"
for p in DatasourceVariable StaticListVariable TimeSeriesChart Markdown; do
	ls -d /srv/perses/plugins/"$p"-* >/dev/null 2>&1 || fail "plugin $p not unpacked into data_dir:
$(ls -la /srv/perses/plugins)"
done
[ -f /srv/perses/plugins/plugin-modules.json ] || fail "no plugin-modules.json in data_dir/plugins"
ls /srv/perses/db/dashboards/test/home.json >/dev/null 2>&1 ||
	ls -R /srv/perses/db | grep -q home || fail "the dashboard is not in data_dir/db:
$(ls -R /srv/perses/db)"
if grep -qi "permission denied\|read-only file system" /tmp/perses.log; then
	fail "it could not use a path it was given:
$(cat /tmp/perses.log)"
fi

# A changed set of archives starts the unpacked plugins over; the same set
# keeps them.
touch /srv/perses/plugins/stale
start >/dev/null
[ -e /srv/perses/plugins/stale ] || fail "plugins reset with the same archives"
cp /usr/share/perses/plugins-archive/Markdown-*.tar.gz /usr/share/perses/plugins-archive/Extra-0.0.1.tar.gz
start >/dev/null
rm /usr/share/perses/plugins-archive/Extra-0.0.1.tar.gz
[ ! -e /srv/perses/plugins/stale ] || fail "plugins kept after the archives changed"

# Logins, guest permissions and an OIDC provider become their variables.
uci set perses.main.auth=1
uci set perses.main.native_login=0
uci add_list perses.main.guest_action=read
uci set perses.main.explorer=1
uci add perses oidc >/dev/null
uci set perses.@oidc[-1].slug_id=test
uci set perses.@oidc[-1].name='Test ID'
uci set perses.@oidc[-1].issuer=https://id.example.com
uci set perses.@oidc[-1].client_id=client
uci set perses.@oidc[-1].client_secret_file=/etc/perses/test-secret
uci commit perses
out=$(start) || fail "did not start with auth: $out"
p=PERSES_SECURITY_AUTHENTICATION_PROVIDERS_OIDC_0_
want \
	"env PERSES_SECURITY_ENABLE_AUTH=true" \
	"env PERSES_SECURITY_AUTHENTICATION_PROVIDERS_ENABLE_NATIVE=false" \
	"env PERSES_SECURITY_AUTHORIZATION_PROVIDER_NATIVE_ENABLE=true" \
	"env PERSES_SECURITY_AUTHORIZATION_PROVIDER_NATIVE_GUEST_PERMISSIONS_0_ACTIONS_0=read" \
	"env PERSES_SECURITY_AUTHORIZATION_PROVIDER_NATIVE_GUEST_PERMISSIONS_0_SCOPES_0=*" \
	"env PERSES_FRONTEND_EXPLORER_ENABLE=true" \
	"env ${p}SLUG_ID=test" \
	"env ${p}NAME=Test ID" \
	"env ${p}ISSUER=https://id.example.com" \
	"env ${p}CLIENT_ID=client" \
	"env ${p}CLIENT_SECRET_FILE=/etc/perses/test-secret" \
	"env ${p}SCOPES_0=openid" \
	"env ${p}SCOPES_2=email"

# An oidc section without its issuer stops it.
uci delete perses.@oidc[-1].issuer
uci commit perses
out=$(start) && fail "started with an oidc section without issuer"
echo "$out" | grep -q "needs slug_id, issuer and client_id" || fail "bad oidc not reported: $out"
uci delete perses.@oidc[-1]
uci commit perses

# An env entry for a variable an option sets, by name or by index, is
# refused, and so is one that is not a PERSES_ setting.
for bad in PERSES_PLUGIN_PATH=/tmp PERSES_PROVISIONING_FOLDERS_1=/tmp PATH=/tmp; do
	uci add_list perses.main.env="$bad"
	uci commit perses
	out=$(start) && fail "started with an env entry $bad"
	echo "$out" | grep -q "set from an option\|is not PERSES_" || fail "env entry $bad not reported: $out"
	uci del_list perses.main.env="$bad"
	uci commit perses
done

# An invalid option stops it.
uci set perses.main.log_level=loud
uci commit perses
out=$(start) && fail "started with log_level=loud"
echo "$out" | grep -q "invalid configuration" || fail "invalid config not reported: $out"

echo "perses: ok"
