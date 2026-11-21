#!/bin/sh
# Smoke test, run by scripts/test.sh in a privileged OpenWrt rootfs with the
# package installed. There is no procd there: the init script's start_service
# runs with procd's calls replaced by ones that print them, and the service
# then runs in ujail as procd would start it, to check it comes up there.
set -eu

fail() { echo "victoria-logs test: $*" >&2; exit 1; }

/usr/bin/victoria-logs -version | grep -q 'v1\.' || fail "victoria-logs -version"
/etc/init.d/victoria-logs enabled || fail "the service is not enabled on install"
grep -q '^victoria-logs:' /etc/passwd || fail "no victoria-logs user"
[ "$(uci -q get victoria-logs.main.listen)" = 127.0.0.1:9428 ] || fail "no default UCI config"

# start: run the init script's start_service, printing what it asks of procd.
start() {
	sh -c '
		. /lib/functions.sh
		. /lib/functions/procd.sh
		initscript=/etc/init.d/victoria-logs
		procd_open_instance() { :; }
		procd_close_instance() { :; }
		procd_set_param() { echo "set $*"; }
		procd_append_param() { echo "append $*"; }
		procd_add_jail() { echo "jail $*"; }
		procd_add_jail_mount() { for a; do echo "mount $a"; done; }
		procd_add_jail_mount_rw() { for a; do echo "mount_rw $a"; done; }
		. /etc/init.d/victoria-logs
		start_service
	' 2>&1
}

out=$(start) && fail "started without a data_dir"
echo "$out" | grep -q "no data_dir" || fail "no data_dir: $out"

uci set victoria-logs.main.data_dir=/srv/victoria-logs
uci add victoria-logs syslog >/dev/null
uci set victoria-logs.@syslog[-1].listen=127.0.0.1:11514
uci set victoria-logs.@syslog[-1].tenant=1:0
uci add victoria-logs syslog >/dev/null
uci set victoria-logs.@syslog[-1].proto=udp
uci set victoria-logs.@syslog[-1].listen=127.0.0.1:11515
uci commit victoria-logs
# A data_dir that already exists, owned by root: handed over, contents too.
mkdir -p /srv/victoria-logs
touch /srv/victoria-logs/before
out=$(start) || fail "did not start: $out"
for want in \
	"set command /usr/bin/victoria-logs -storageDataPath=/srv/victoria-logs -retentionPeriod=7d -httpListenAddr=127.0.0.1:9428 -memory.allowedBytes=64MB -loggerLevel=INFO -loggerOutput=stdout" \
	"append command -syslog.listenAddr.tcp=127.0.0.1:11514" \
	"append command -syslog.tenantID.tcp=1:0" \
	"append command -syslog.listenAddr.udp=127.0.0.1:11515" \
	"append command -syslog.tenantID.udp=0:0" \
	"set env GOMEMLIMIT=128MiB" \
	"jail victoria-logs log procfs requirejail" \
	"mount_rw /srv/victoria-logs" \
	"set user victoria-logs" \
	"set no_new_privs 1" \
	"set term_timeout 60"; do
	echo "$out" | grep -qxF "$want" || fail "missing \"$want\" in:
$out"
done
echo "$out" | grep -q "in RAM" && fail "warned about RAM for /srv: $out"
[ "$(ls -ld /srv/victoria-logs | awk '{print $3}')" = victoria-logs ] || fail "data_dir not owned by victoria-logs"
[ "$(ls -l /srv/victoria-logs/before | awk '{print $3}')" = victoria-logs ] || fail "data_dir contents not handed over"
# Once it is its own, a start does not walk it again.
touch /srv/victoria-logs/after
start >/dev/null
[ "$(ls -l /srv/victoria-logs/after | awk '{print $3}')" = root ] || fail "re-owned data_dir on a later start"

# The jail it asked for is enough to run in. ujail talks to ubus.
pidof ubusd >/dev/null || { ubusd & sleep 1; }
jail="-n victoria-logs -E -c -p -U victoria-logs -G victoria-logs -e GOMEMLIMIT"
for m in $(echo "$out" | sed -n 's/^mount //p'); do jail="$jail -r $m"; done
for m in $(echo "$out" | sed -n 's/^mount_rw //p'); do jail="$jail -w $m"; done
cmd=$(echo "$out" | sed -n 's/^set command //p; s/^append command //p' | tr '\n' ' ')
# shellcheck disable=SC2086  # word-split on purpose: options and arguments
GOMEMLIMIT=128MiB /sbin/ujail $jail -- $cmd > /tmp/victoria-logs.log 2>&1 &
pid=$!
health=
for _ in 1 2 3 4 5 6 7 8 9 10; do
	sleep 1
	health=$(wget -qO- http://127.0.0.1:9428/health 2>/dev/null) && break
done
# A syslog line on the input it was given, stored and found again.
printf '<14>1 %s testhost cacimba - - - cacimba-test-line\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" |
	nc 127.0.0.1 11514 2>/dev/null || true
found=
for _ in 1 2 3 4 5 6 7 8 9 10; do
	sleep 1
	# Under the tenant its input stores to (1:0).
	found=$(wget -qO- --header 'AccountID: 1' --header 'ProjectID: 0' \
		'http://127.0.0.1:9428/select/logsql/query?query=cacimba-test-line' 2>/dev/null) || true
	[ -n "$found" ] && break
done
kill "$pid" 2>/dev/null || true
[ "$health" = OK ] || fail "victoria-logs did not come up in its jail:
$(cat /tmp/victoria-logs.log)"
echo "$found" | grep -q cacimba-test-line || fail "the syslog line was not stored:
$(cat /tmp/victoria-logs.log)"
[ -n "$(ls /srv/victoria-logs)" ] || fail "nothing written to data_dir"

# data_dir in RAM: starts, with a warning.
mkdir -p /tmp/ram
mount -t tmpfs tmpfs /tmp/ram
uci set victoria-logs.main.data_dir=/tmp/ram/victoria-logs
uci commit victoria-logs
out=$(start) || fail "did not start with data_dir in RAM: $out"
echo "$out" | grep -q "in RAM" || fail "no warning for data_dir in RAM: $out"
umount /tmp/ram

# Without a listen option it falls back to its default, port included.
uci delete victoria-logs.main.listen
uci commit victoria-logs
out=$(start) || fail "did not start without a listen option: $out"
echo "$out" | grep -q -- "-httpListenAddr=127.0.0.1:9428 " || fail "wrong default listen: $out"
uci set victoria-logs.main.listen=127.0.0.1:9428
uci commit victoria-logs

# An invalid syslog input stops it.
uci set victoria-logs.@syslog[-1].proto=smoke
uci commit victoria-logs
uci set victoria-logs.main.data_dir=/srv/victoria-logs
uci commit victoria-logs
out=$(start) && fail "started with syslog proto=smoke"
echo "$out" | grep -q "invalid syslog section" || fail "invalid syslog not reported: $out"
uci set victoria-logs.@syslog[-1].proto=udp
uci commit victoria-logs

# An invalid option stops it.
uci set victoria-logs.main.data_dir=/srv/victoria-logs
uci set victoria-logs.main.log_level=LOUD
uci commit victoria-logs
out=$(start) && fail "started with log_level=LOUD"
echo "$out" | grep -q "invalid configuration" || fail "invalid config not reported: $out"

echo "victoria-logs: ok"
