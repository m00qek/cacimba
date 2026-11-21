#!/bin/sh
# Install built packages in an OpenWrt rootfs container and run their tests.
#
# Usage:
#   test.sh IMAGE BUILD PACKAGE...
#       In the rootfs image IMAGE, e.g. openwrt/rootfs:x86_64-25.12.6,
#       install the apks under BUILD/<PACKAGE>/ (the OUT of build.sh) with
#       their dependencies from OpenWrt's feeds, then run each package's
#       openwrt/<PACKAGE>/test.sh, if it has one.
#
#       The container is privileged, so a package's test can run its service
#       in ujail as procd would.
#
#       The packages are unsigned here (build.sh output), so they are
#       installed with --allow-untrusted; the feed signs them on publish.
#
# POSIX sh on the runner, plus docker.

set -eu
export LC_ALL=C

[ $# -ge 3 ] || { sed -n '/^# Usage:/,/^# POSIX/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
image=$1 build=$2
shift 2

root=$(cd "$(dirname "$0")/.." && pwd)
build=$(cd "$build" && pwd)

for p in "$@"; do
	set -- "$build/$p"/*.apk
	[ -f "$1" ] || { echo "::error::test.sh: no apk built for $p" >&2; exit 1; }
	echo "== $p"
	tests=
	[ -f "$root/openwrt/$p/test.sh" ] && tests="-v $root/openwrt/$p/test.sh:/test.sh:ro"
	# shellcheck disable=SC2086  # $tests: one -v option, a path without spaces
	docker run --rm --privileged -v "$build/$p":/pkgs:ro $tests "$image" sh -c '
		set -e
		mkdir -p /var/lock /var/run
		apk update >/dev/null
		apk add --allow-untrusted /pkgs/*.apk
		# Every package here runs a service: an upgrade must restart it, or
		# the old version keeps running under the new one.
		for f in /pkgs/*.apk; do
			apk adbdump "$f" | grep -q "init.d/.* restart" ||
				{ echo "$f: its upgrade does not restart the service" >&2; exit 1; }
		done
		if [ -f /test.sh ]; then sh /test.sh; else echo "no test.sh: installed only"; fi
	'
done
