#!/bin/sh
# Smoke test, run by scripts/test.sh in a privileged OpenWrt rootfs with the
# package installed. There is no procd there: the init script's start_service
# runs with procd's calls replaced by ones that print them, and the service
# then runs in ujail as procd would start it, to check it comes up there.
set -eu

fail() { echo "victoria-metrics test: $*" >&2; exit 1; }

/usr/bin/victoria-metrics -version | grep -q 'v1\.' || fail "victoria-metrics -version"
/etc/init.d/victoria-metrics enabled || fail "the service is not enabled on install"
grep -q '^victoria-metrics:' /etc/passwd || fail "no victoria-metrics user"
[ "$(uci -q get victoria-metrics.main.listen)" = 127.0.0.1:8428 ] || fail "no default UCI config"

# start: run the init script's start_service, printing what it asks of procd.
start() {
	sh -c '
		. /lib/functions.sh
		. /lib/functions/procd.sh
		initscript=/etc/init.d/victoria-metrics
		procd_open_instance() { :; }
		procd_close_instance() { :; }
		procd_set_param() { echo "set $*"; }
		procd_append_param() { echo "append $*"; }
		procd_add_jail() { echo "jail $*"; }
		procd_add_jail_mount() { for a; do echo "mount $a"; done; }
		procd_add_jail_mount_rw() { for a; do echo "mount_rw $a"; done; }
		. /etc/init.d/victoria-metrics
		start_service
	' 2>&1
}

out=$(start) && fail "started without a data_dir"
echo "$out" | grep -q "no data_dir" || fail "no data_dir: $out"

uci set victoria-metrics.main.data_dir=/srv/victoria-metrics
uci commit victoria-metrics
out=$(start) || fail "did not start: $out"
for want in \
	"set command /usr/bin/victoria-metrics -storageDataPath=/srv/victoria-metrics -retentionPeriod=30d -httpListenAddr=127.0.0.1:8428 -memory.allowedBytes=64MB -loggerLevel=INFO -loggerOutput=stdout" \
	"set env GOMEMLIMIT=128MiB" \
	"jail victoria-metrics log procfs requirejail" \
	"mount_rw /srv/victoria-metrics" \
	"set user victoria-metrics" \
	"set no_new_privs 1" \
	"set term_timeout 60"; do
	echo "$out" | grep -qxF "$want" || fail "missing \"$want\" in:
$out"
done
echo "$out" | grep -q "in RAM" && fail "warned about RAM for /srv: $out"
[ "$(ls -ld /srv/victoria-metrics | awk '{print $3}')" = victoria-metrics ] || fail "data_dir not owned by victoria-metrics"

# The jail it asked for is enough to run in. ujail talks to ubus.
pidof ubusd >/dev/null || { ubusd & sleep 1; }
jail="-n victoria-metrics -E -c -p -U victoria-metrics -G victoria-metrics -e GOMEMLIMIT"
for m in $(echo "$out" | sed -n 's/^mount //p'); do jail="$jail -r $m"; done
for m in $(echo "$out" | sed -n 's/^mount_rw //p'); do jail="$jail -w $m"; done
cmd=$(echo "$out" | sed -n 's/^set command //p; s/^append command //p' | tr '\n' ' ')
# shellcheck disable=SC2086  # word-split on purpose: options and arguments
GOMEMLIMIT=128MiB /sbin/ujail $jail -- $cmd > /tmp/victoria-metrics.log 2>&1 &
pid=$!
health=
for _ in 1 2 3 4 5 6 7 8 9 10; do
	sleep 1
	health=$(wget -qO- http://127.0.0.1:8428/health 2>/dev/null) && break
done
# It stores what it is sent, in the jail's data_dir.
wget -qO- --post-data='cacimba_test 1' http://127.0.0.1:8428/api/v1/import/prometheus >/dev/null 2>&1 || true
kill "$pid" 2>/dev/null || true
[ "$health" = OK ] || fail "victoria-metrics did not come up in its jail:
$(cat /tmp/victoria-metrics.log)"
[ -d /srv/victoria-metrics/data ] || fail "nothing written to data_dir"

# data_dir in RAM: starts, with a warning.
mkdir -p /tmp/ram
mount -t tmpfs tmpfs /tmp/ram
uci set victoria-metrics.main.data_dir=/tmp/ram/victoria-metrics
uci commit victoria-metrics
out=$(start) || fail "did not start with data_dir in RAM: $out"
echo "$out" | grep -q "in RAM" || fail "no warning for data_dir in RAM: $out"
umount /tmp/ram

# Without a listen option it falls back to its default, port included.
uci delete victoria-metrics.main.listen
uci commit victoria-metrics
out=$(start) || fail "did not start without a listen option: $out"
echo "$out" | grep -q -- "-httpListenAddr=127.0.0.1:8428 " || fail "wrong default listen: $out"
uci set victoria-metrics.main.listen=127.0.0.1:8428
uci commit victoria-metrics

# An invalid option stops it.
uci set victoria-metrics.main.data_dir=/srv/victoria-metrics
uci set victoria-metrics.main.log_level=LOUD
uci commit victoria-metrics
out=$(start) && fail "started with log_level=LOUD"
echo "$out" | grep -q "invalid configuration" || fail "invalid config not reported: $out"

echo "victoria-metrics: ok"
