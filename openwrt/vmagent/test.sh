#!/bin/sh
# Smoke test, run by scripts/test.sh in an OpenWrt rootfs with the package
# installed. There is no procd or ubus there, so the service is not started:
# this checks what the package installed, and runs the init script's
# start_service with procd's calls replaced by ones that print them.
set -eu

fail() { echo "vmagent test: $*" >&2; exit 1; }

/usr/bin/vmagent -version | grep -q 'v1\.' || fail "vmagent -version"
/etc/init.d/vmagent enabled || fail "the service is not enabled on install"
grep -q '^vmagent:' /etc/passwd || fail "no vmagent user"
grep -q '^vmagent:' /etc/group || fail "no vmagent group"
[ "$(uci -q get vmagent.main.listen)" = 127.0.0.1:8429 ] || fail "no default UCI config"
[ -f /etc/vmagent/scrape.yml ] || fail "no default scrape config"

# The default scrape config must parse: -dryRun checks it and exits.
/usr/bin/vmagent -dryRun -promscrape.config=/etc/vmagent/scrape.yml \
	-remoteWrite.url=http://127.0.0.1:8428/api/v1/write >/dev/null 2>&1 ||
	fail "the default scrape config does not parse"

# start: run the init script's start_service, printing what it asks of procd.
start() {
	sh -c '
		. /lib/functions.sh
		. /lib/functions/procd.sh
		initscript=/etc/init.d/vmagent
		procd_open_instance() { :; }
		procd_close_instance() { :; }
		procd_set_param() { echo "set $*"; }
		procd_append_param() { echo "append $*"; }
		procd_add_jail() { echo "jail $*"; }
		procd_add_jail_mount() { for a; do echo "mount $a"; done; }
		procd_add_jail_mount_rw() { for a; do echo "mount_rw $a"; done; }
		. /etc/init.d/vmagent
		start_service
	' 2>&1
}

out=$(start) && fail "started without a remote_write"
echo "$out" | grep -q "no remote_write" || fail "no remote_write: $out"

uci add_list vmagent.main.remote_write=http://127.0.0.1:8428/api/v1/write
uci add_list vmagent.main.remote_write=http://10.0.0.1:8428/api/v1/write
uci add_list vmagent.main.label=site=test
uci set vmagent.main.gomemlimit=96MiB
uci commit vmagent
out=$(start) || fail "did not start: $out"
for want in \
	"set command /usr/bin/vmagent -promscrape.config=/etc/vmagent/scrape.yml -remoteWrite.tmpDataPath=/var/lib/vmagent -remoteWrite.maxDiskUsagePerURL=16MB -httpListenAddr=127.0.0.1:8429 -loggerLevel=INFO -loggerOutput=stdout" \
	"append command -memory.allowedBytes=32MB" \
	"append command -remoteWrite.url=http://127.0.0.1:8428/api/v1/write" \
	"append command -remoteWrite.url=http://10.0.0.1:8428/api/v1/write" \
	"append command -remoteWrite.label=site=test" \
	"set env GOMEMLIMIT=96MiB" \
	"jail vmagent log procfs requirejail" \
	"mount /etc/vmagent/scrape.yml" \
	"mount /etc/ssl/certs" \
	"mount_rw /var/lib/vmagent" \
	"set user vmagent" \
	"set no_new_privs 1" \
	"set term_timeout 30" \
	"set file /etc/vmagent/scrape.yml"; do
	echo "$out" | grep -qxF "$want" || fail "missing \"$want\" in:
$out"
done
[ "$(ls -ld /var/lib/vmagent | awk '{print $3}')" = vmagent ] || fail "data_dir not owned by vmagent"

# The jail it asked for is enough to run in: start vmagent in ujail as procd
# would (needs a privileged container), with the same mounts, user and
# command, and ask it for its health. ujail talks to ubus, as on a router.
pidof ubusd >/dev/null || { ubusd & sleep 1; }
jail="-n vmagent -E -c -p -U vmagent -G vmagent -e GOMEMLIMIT"
for m in $(echo "$out" | sed -n 's/^mount //p'); do jail="$jail -r $m"; done
for m in $(echo "$out" | sed -n 's/^mount_rw //p'); do jail="$jail -w $m"; done
cmd=$(echo "$out" | sed -n 's/^set command //p; s/^append command //p' | tr '\n' ' ')
# shellcheck disable=SC2086  # word-split on purpose: options and arguments
GOMEMLIMIT=96MiB /sbin/ujail $jail -- $cmd > /tmp/vmagent.log 2>&1 &
pid=$!
health=
for _ in 1 2 3 4 5 6 7 8 9 10; do
	sleep 1
	health=$(wget -qO- http://127.0.0.1:8429/health 2>/dev/null) && break
done
kill "$pid" 2>/dev/null || true
[ "$health" = OK ] || fail "vmagent did not come up in its jail:
$(cat /tmp/vmagent.log)"

# Without a listen option it falls back to its default, port included.
uci delete vmagent.main.listen
uci commit vmagent
out=$(start) || fail "did not start without a listen option: $out"
echo "$out" | grep -q -- "-httpListenAddr=127.0.0.1:8429 " || fail "wrong default listen: $out"
uci set vmagent.main.listen=127.0.0.1:8429
uci commit vmagent

uci set vmagent.main.enabled=maybe
uci commit vmagent
out=$(start) && fail "started with enabled=maybe"
echo "$out" | grep -q "invalid configuration" || fail "invalid config not reported: $out"
uci set vmagent.main.enabled=1
uci commit vmagent

# A data_dir on a declared mount that is not mounted: wait, start nothing.
uci set vmagent.main.data_dir=/mnt/data/vmagent
uci commit vmagent
touch /etc/config/fstab
uci add fstab mount >/dev/null
uci set fstab.@mount[-1].target=/mnt/data
uci commit fstab
out=$(start) || fail "failed instead of waiting for the mount: $out"
echo "$out" | grep -q "not mounted yet" || fail "did not wait for the mount: $out"
echo "$out" | grep -q "^set command" && fail "started before the mount: $out"
[ ! -e /mnt/data/vmagent ] || fail "created data_dir on the unmounted path"

echo "vmagent: ok"
