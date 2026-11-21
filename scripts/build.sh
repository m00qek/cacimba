#!/bin/sh
# Build feed packages in an OpenWrt SDK container.
#
# Usage:
#   build.sh RELEASE IMAGE BUILD OUT PACKAGE...
#       Build the feed's openwrt/PACKAGE directories with the SDK image IMAGE,
#       e.g. openwrt/sdk:aarch64_generic-25.12.6, for RELEASE, e.g. 25.12, and
#       copy the package files each produced to OUT/<PACKAGE>/.
#
#       BUILD is `noarch` for packages with nothing architecture-specific
#       (feed.json's "build": "noarch"), or the package architecture IMAGE
#       builds for, e.g. aarch64_generic, for packages that wrap an upstream
#       binary ("build": "prebuilt"). Neither compiles anything, so the
#       packages' dependencies are not built (NO_DEPS); the package manager
#       still records them, and the router installs them from OpenWrt's feeds.
#
#       Every feed is switched from the release tag the image pins to the
#       release's branch, openwrt-RELEASE, which is what routers on any point
#       release of the series install dependencies from.
#
#       A build that produces none, or not all, of a package's packages, as
#       tmp/.packageinfo lists them, or a file of another release, fails.
#
# POSIX sh on the runner, plus docker.

set -eu
export LC_ALL=C

fail() {
	echo "::error::build.sh: $*" >&2
	exit 1
}

[ $# -ge 5 ] || { sed -n '/^# Usage:/,/^# POSIX/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
release=$1 image=$2 build=$3 out=$4
shift 4

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
# The SDK runs as its own user (buildbot, uid 1000), which the runner's user
# need not be. The build makes what it writes removable before it ends; if it
# failed first, what remains is left behind rather than failing the cleanup.
trap 'rm -rf "$work" 2>/dev/null || true' EXIT INT TERM
mkdir -p "$work/pkg" "$work/bin" "$work/out" "$out"
out=$(cd "$out" && pwd)

mounts=
targets=
for p in "$@"; do
	src=$root/openwrt/$p
	[ -f "$src/Makefile" ] || fail "$p: no openwrt/$p/Makefile"
	r=$(sed -n 's/^PKG_RELEASE:=//p' "$src/Makefile")
	[ -n "$r" ] || fail "openwrt/$p/Makefile has no PKG_RELEASE"
	cp -R "$src" "$work/pkg/$p"
	echo "$p $r" >> "$work/releases"
	echo "$p: release r$r"
	mounts="$mounts -v $work/pkg/$p:/builder/package/$p:ro"
	targets="$targets package/$p/compile"
done

chmod 777 "$work/bin" "$work/out"
# shellcheck disable=SC2086  # $mounts: -v options, paths without spaces
docker run --rm $mounts \
	-v "$work/bin":/builder/bin -v "$work/out":/out -v "$work/releases":/releases:ro \
	"$image" sh -c '
		set -e
		sed -i -E "/^src-git/s/[;^][^;^]*\$/;openwrt-'"$release"'/" feeds.conf.default
		cat feeds.conf.default
		./scripts/feeds update -a
		./scripts/feeds install -a
		make defconfig
		make '"$targets"' NO_DEPS=1 CHECK_KEY=0 V=s

		# Each package directory produces the packages tmp/.packageinfo lists
		# under its Makefile: one file each, <name>-<version>.apk. A version
		# starts with a digit, so a name is never mistaken for a longer one
		# that starts with it.
		while read -r p r; do
			mkdir -p "/out/$p"
			names=$(awk -v m="package/$p/Makefile" "
				/^Source-Makefile: /{ on = (\$2 == m); next }
				on && /^Package: /{ print \$2 }" tmp/.packageinfo)
			[ -n "$names" ] || { echo "$p: tmp/.packageinfo lists no package" >&2; exit 1; }
			for n in $names; do
				files=$(find /builder/bin -type f -name "${n}-[0-9]*.apk")
				count=$(printf "%s" "$files" | grep -c . || true)
				[ "$count" -eq 1 ] || { echo "$p: expected one file for $n, found $count: $files" >&2; exit 1; }
				cp "$files" "/out/$p/"
			done
		done < /releases
		# What it wrote, not the mount points, which are the runner'"'"'s.
		find /out /builder/bin -mindepth 1 -exec chmod a+rwX {} +
	'

# Every file must carry the release the build was asked for:
# <name>-<version>-r<N>.apk.
while read -r p r; do
	for f in "$work/out/$p"/*; do
		case "$(basename "$f")" in
			*-r"$r".apk) ;;
			*) fail "$p: $(basename "$f") is not release r$r" ;;
		esac
	done
	echo "$p:"
	ls -1 "$work/out/$p" | sed 's/^/  /'
done < "$work/releases"
cp -R "$work/out"/. "$out/"
