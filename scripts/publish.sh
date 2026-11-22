#!/bin/sh
# File built packages into the feed, prune old versions, regenerate indexes.
#
# The feed workflow runs this, so the feed layout, the signing and the index
# rules exist once. The layout of a feed checkout (gh-pages, openwrt/):
#
#   <release>/noarch/     architecture-independent packages; every arch index
#                         lists them, apk downloads them from here
#   <release>/<arch>/     packages for <arch>, APKINDEX.tar.gz, and
#                         packages.adb with its index.json (apk_release)
#   <release>/feed.pub.pem  the key the packages and indexes are signed with
#
# Usage:
#   publish.sh file STAGING FEED
#       File the packages under STAGING/<release>/<build>/ into the feed
#       checkout FEED. <build> is the package architecture a build job built
#       for, e.g. aarch64_generic, or `noarch`. Each apk is signed first.
#       A file already in the feed is never replaced, so a published version
#       stays downloadable as it was.
#
#   publish.sh prune [--keep N] [--keep-package NAME=N]... FEED
#       Delete all but the newest N (default 3) versions of each package in
#       each directory of FEED: the current one, and two to roll back to.
#       --keep-package keeps another number of the package NAME.
#
#   publish.sh index [--manifest FEED_JSON] [--pubkeys DIR] FEED
#       Regenerate and sign every index in FEED. Each index lists only the
#       newest version of a package.
#
#       With --manifest, a release also gets an index for each arch in its
#       "index-arches" in FEED_JSON (feed.json), whether or not any package
#       is built for it: apk reads <release>/<arch>/APKINDEX.tar.gz only, so
#       the noarch packages reach a router only through an index for its
#       arch. With --pubkeys, DIR/apk.pub is copied in as
#       <release>/feed.pub.pem.
#
# Environment:
#   APK_FEED_SIGNING_KEY    apk private key (PEM); unset: apks stay unsigned
#   APK_IMAGE               SDK image with apk-tools 3
#                           (default: openwrt/sdk:x86-64-25.12.6)
#
# POSIX sh on the runner, plus docker, and jq for --manifest: the feed tools
# come from the SDK image.

set -eu
export LC_ALL=C

HERE=$(cd "$(dirname "$0")" && pwd)
APK_IMAGE=${APK_IMAGE:-openwrt/sdk:x86-64-25.12.6}
HOSTBIN=/builder/staging_dir/host/bin

fail() {
	echo "::error::publish.sh: $*" >&2
	exit 1
}
usage() {
	sed -n '/^# Usage:/,/^# Environment:/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
	exit 2
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# The key goes to a directory every container mounts read-only at /keys.
mkdir -p "$WORK/keys"
if [ -n "${APK_FEED_SIGNING_KEY:-}" ]; then
	printf '%s' "$APK_FEED_SIGNING_KEY" > "$WORK/keys/apk.key"
fi

# sdk [docker run options...] -- COMMAND...: run COMMAND in the SDK image as
# the runner's user, with this directory at /scripts and the key at /keys.
sdk() {
	opts=
	while [ "$1" != -- ]; do
		opts="$opts $1"
		shift
	done
	shift
	# shellcheck disable=SC2086  # $opts is a list of mount options without spaces
	docker run --rm --user "$(id -u):$(id -g)" \
		-v "$HERE":/scripts:ro -v "$WORK/keys":/keys:ro \
		$opts "$APK_IMAGE" "$@"
}

# ---------------------------------------------------------------------- file

# put PACKAGE DIR: file PACKAGE into DIR, unless it is published already.
put() {
	base=$(basename "$1")
	if [ -e "$2/$base" ]; then
		echo "kept   $2/$base (already published)"
		return
	fi
	mkdir -p "$2"
	cp "$1" "$2/"
	echo "filed  $2/$base"
}

# arch_of PACKAGE: the architecture it is built for, read when it was signed
# (not from its name: names and architectures both contain '_' and '-').
arch_of() {
	a=$(cat "$1.arch")
	[ -n "$a" ] || fail "no architecture in $1"
	case "$a" in all | noarch) echo noarch ;; *) echo "$a" ;; esac
}

# sign_apks RELEASE: sign the release's staged apks and record each one's
# arch next to it. Reading an apk takes apk-tools, from the SDK.
sign_apks() {
	chmod -R 777 "$WORK/new/$1"
	sdk -v "$WORK/new/$1":/new -- sh -c '
		set -e
		for pkg in /new/*/*.apk; do
			if [ -f /keys/apk.key ]; then
				'"$HOSTBIN"'/apk adbsign --allow-untrusted --reset-signatures \
					--sign-key /keys/apk.key "$pkg"
			fi
			arch=$('"$HOSTBIN"'/apk adbdump "$pkg" 2>/dev/null | awk "/^ *arch:/{print \$2}")
			[ -n "$arch" ] || { echo "no arch in $pkg" >&2; exit 1; }
			echo "$arch" > "$pkg.arch"
		done
	'
}

cmd_file() {
	[ $# -eq 2 ] || usage
	[ -d "$1" ] || fail "no staging directory $1"
	[ -d "$2" ] || fail "no feed directory $2"
	feed=$2

	mkdir -p "$WORK/new"
	cp -R "$1"/. "$WORK/new/"

	for rdir in "$WORK"/new/*/; do
		[ -d "$rdir" ] || continue
		rel=$(basename "$rdir")
		[ -n "$(find "$rdir" -name '*.apk' | head -n 1)" ] || fail "$rel: nothing staged"
		sign_apks "$rel"
		for b in $(cd "$rdir" && ls -d -- */ | sed 's,/$,,'); do
			for pkg in "$rdir$b"/*.apk; do
				[ -f "$pkg" ] || continue
				a=$(arch_of "$pkg")
				[ "$a" = "$b" ] || fail "$rel: $(basename "$pkg"), from the $b build, is for $a"
				put "$pkg" "$feed/$rel/$a"
			done
		done
	done
}

# --------------------------------------------------------------------- prune

# name_of FILE: the package name of <name>-<version>-r<N>.apk, as newest.sh
# parses it.
name_of() {
	basename "$1" | sed -E 's/-[0-9][0-9.]*-r[0-9]+\.apk$//'
}

cmd_prune() {
	keep=3
	overrides=
	while [ $# -gt 1 ]; do
		case "$1" in
			--keep) keep=$2; shift 2 ;;
			--keep-package)
				case "$2" in
					?*=[1-9]*) overrides="$overrides $2" ;;
					*) fail "--keep-package: '$2' is not NAME=N" ;;
				esac
				shift 2 ;;
			*) break ;;
		esac
	done
	[ $# -eq 1 ] || usage
	[ -d "$1" ] || fail "no feed directory $1"
	for dir in "$1"/*/*/; do
		set -- "$dir"*.apk
		[ -f "$1" ] || continue
		# Each package with an override is picked on its own, the rest
		# together. Paths have no spaces.
		rest=
		kept=
		for f in "$@"; do
			case " $overrides " in
				*" $(name_of "$f")="*) ;;
				*) rest="$rest $f" ;;
			esac
		done
		# shellcheck disable=SC2086
		[ -z "$rest" ] || kept=$(sh "$HERE/newest.sh" --keep "$keep" $rest)
		for o in $overrides; do
			mine=
			for f in "$@"; do
				[ "$(name_of "$f")" = "${o%%=*}" ] && mine="$mine $f"
			done
			# shellcheck disable=SC2086
			[ -z "$mine" ] || kept="$kept
$(sh "$HERE/newest.sh" --keep "${o#*=}" $mine)"
		done
		for f in "$@"; do
			if ! printf '%s\n' "$kept" | grep -qxF "$f"; then
				rm -f "$f"
				echo "pruned $f"
			fi
		done
	done
}

# --------------------------------------------------------------------- index

# apk only installs what the router's own <arch>/APKINDEX.tar.gz lists, so
# each arch index lists the newest of its own directory and of noarch/. An
# arch with no packages of its own, made for the manifest's index-arches,
# lists only noarch/. All of a release's indexes are built in one container.
#
# Each arch also gets the same index as packages.adb, plus index.json. A
# router's repository line is either the release root, for which apk reads
# <arch>/APKINDEX.tar.gz and fetches <root>/<pkg arch>/<pkg>.apk, or the full
# URL of an index, as OpenWrt's own distfeeds are, for which apk fetches each
# package relative to the index's directory. packages.adb is for the second
# kind: its pkgname-spec points back up to the package's own arch directory,
# noarch/ included. owut and the ASU server only work with the second kind,
# and read index.json next to it, made by the SDK's make-index-json.py the
# same way OpenWrt makes its own.
apk_release() {
	mkdir -p "$1/noarch"
	chmod -R 777 "$1" || true
	sdk -v "$(cd "$1" && pwd)":/release -- sh -c "
		set -e
		for dir in /release/*/; do
			[ \"\$dir\" != /release/noarch/ ] || continue
			files=
			for f in /release/noarch/*.apk \"\$dir\"*.apk; do
				if [ -f \"\$f\" ]; then files=\"\$files \$f\"; fi
			done
			# Nothing for this arch: no index (apk cannot read an empty one),
			# and no directory, so an arch the feed has nothing for is absent.
			if [ -z \"\$files\" ]; then
				rm -f \"\$dir\"APKINDEX.tar.gz \"\$dir\"packages.adb \"\$dir\"index.json
				rmdir \"\$dir\"
				continue
			fi
			newest=\$(sh /scripts/newest.sh \$files)
			$HOSTBIN/apk mkndx --allow-untrusted -o \"\${dir}APKINDEX.tar.gz\" \$newest
			$HOSTBIN/apk mkndx --allow-untrusted -o \"\${dir}packages.adb\" \
				--pkgname-spec '../\${arch}/\${name}-\${version}.apk' \$newest
			for index in APKINDEX.tar.gz packages.adb; do
				if [ -f /keys/apk.key ]; then
					$HOSTBIN/apk adbsign --allow-untrusted --reset-signatures \
						--sign-key /keys/apk.key \"\${dir}\$index\"
				fi
			done
			$HOSTBIN/apk adbdump --format json \"\${dir}packages.adb\" |
				python3 /builder/scripts/make-index-json.py -f apk -a \"\$(basename \"\$dir\")\" - \
				> \"\${dir}index.json\"
		done
	"
}

cmd_index() {
	pubkeys=
	manifest=
	while [ $# -gt 0 ]; do
		case "$1" in
			--pubkeys) pubkeys=$2; shift ;;
			--manifest) manifest=$2; shift ;;
			-*) usage ;;
			*) break ;;
		esac
		shift
	done
	[ $# -eq 1 ] || usage
	[ -d "$1" ] || fail "no feed directory $1"

	for rdir in "$1"/*/; do
		[ -d "$rdir" ] || continue
		rdir=${rdir%/}
		if [ -n "$manifest" ]; then
			arches=$(jq -r --arg r "$(basename "$rdir")" \
				'.releases[$r]["index-arches"] // [] | .[]' "$manifest") ||
				fail "could not read the index-arches of $(basename "$rdir") from $manifest"
			for a in $arches; do mkdir -p "$rdir/$a"; done
		fi
		apk_release "$rdir"
		if [ -n "$pubkeys" ]; then cp "$pubkeys/apk.pub" "$rdir/feed.pub.pem"; fi
	done
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
	file) cmd_file "$@" ;;
	prune) cmd_prune "$@" ;;
	index) cmd_index "$@" ;;
	*) usage ;;
esac
