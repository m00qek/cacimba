#!/bin/sh
# Pick the newest versions of each package among apk files.
#
# The feed keeps the newest --keep versions of each package on gh-pages, so a
# rollback by direct download keeps working without the branch growing with
# every release of a large binary. The indexes, like OpenWrt's own feeds, list
# one version per package: LuCI's Software page shows one row per package
# name and picks whichever entry it sees.
#
# Usage:
#   newest.sh [--keep N] FILE.apk...
#       Print, one per line, the newest N (default 1) FILEs of each package
#       name, newest first. Name and version come from the filename
#       <name>-<version>-r<release>.apk, parsed from the right, since names
#       contain '-'.
#
# Versions are compared with opkg's algorithm (libopkg pkg_compare_versions:
# epoch, then upstream version, then revision, each with Debian's verrevcmp).
# apk's own ordering agrees with it on <digits>(.<digits>)*-r<digits>, the
# only version shape accepted; anything else fails loudly rather than risk
# indexing, or deleting, the wrong file.
#
# POSIX sh and awk only: it runs in the openwrt/sdk images and on the runner.

set -eu
export LC_ALL=C

# verrevcmp and pkg_compare_versions, ported from opkg's libopkg/pkg.c.
# ord() replaces C's char arithmetic: POSIX awk has no ord builtin.
AWK_VERCMP='
function init_ord(   i) {
	for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
}
function is_digit(c) { return c ~ /^[0-9]$/ }
function order(c) {
	if (c == "~") return -1
	if (c == "" || is_digit(c)) return 0
	if (c ~ /^[A-Za-z]$/) return ORD[c]
	return ORD[c] + 256
}
function verrevcmp(a, b,   i, j, la, lb, ca, cb, oa, ob, diff) {
	i = 1; j = 1; la = length(a); lb = length(b)
	while (i <= la || j <= lb) {
		diff = 0
		while ((i <= la && !is_digit(substr(a, i, 1))) || \
		       (j <= lb && !is_digit(substr(b, j, 1)))) {
			ca = (i <= la) ? substr(a, i, 1) : ""
			cb = (j <= lb) ? substr(b, j, 1) : ""
			oa = order(ca); ob = order(cb)
			if (oa != ob) return oa - ob
			i++; j++
		}
		while (i <= la && substr(a, i, 1) == "0") i++
		while (j <= lb && substr(b, j, 1) == "0") j++
		while (i <= la && j <= lb && is_digit(substr(a, i, 1)) && is_digit(substr(b, j, 1))) {
			if (!diff) diff = substr(a, i, 1) - substr(b, j, 1)
			i++; j++
		}
		if (i <= la && is_digit(substr(a, i, 1))) return 1
		if (j <= lb && is_digit(substr(b, j, 1))) return -1
		if (diff) return diff
	}
	return 0
}
# Split [epoch:]upstream[-revision] the way opkg parse_version does: the
# epoch ends at the first ":", the revision starts after the last "-".
function split_version(v, parts,   k) {
	parts["epoch"] = 0
	if ((k = index(v, ":")) > 0) {
		parts["epoch"] = substr(v, 1, k - 1) + 0
		v = substr(v, k + 1)
	}
	parts["rev"] = ""
	if (match(v, /-[^-]*$/)) {
		parts["rev"] = substr(v, RSTART + 1)
		v = substr(v, 1, RSTART - 1)
	}
	parts["up"] = v
}
function vercmp(a, b,   pa, pb, r) {
	split_version(a, pa); split_version(b, pb)
	if (pa["epoch"] != pb["epoch"]) return pa["epoch"] - pb["epoch"]
	if ((r = verrevcmp(pa["up"], pb["up"])) != 0) return r
	return verrevcmp(pa["rev"], pb["rev"])
}
'

die() {
	echo "newest.sh: $*" >&2
	exit 1
}

keep=1
if [ "${1:-}" = --keep ]; then
	[ "$#" -ge 2 ] || die "--keep needs a number"
	keep=$2
	shift 2
	case "$keep" in '' | 0* | *[!0-9]*) die "--keep: '$keep' is not a number: 1, 2, ..." ;; esac
fi
[ "$#" -gt 0 ] || die "usage: $0 [--keep N] FILE.apk..."
# Checked up front: a die inside the pipeline below would only end a
# subshell, and an unmatched /pkgs/*.apk glob arrives here verbatim.
for f in "$@"; do
	[ -f "$f" ] || die "no such file: $f"
done

printf '%s\n' "$@" | awk -v keep="$keep" "$AWK_VERCMP"'
BEGIN { init_ord() }
{
	path = $0
	base = path; sub(/^.*\//, "", base)
	# <name>-<version>-r<release>.apk; name may contain "-".
	if (!match(base, /-[0-9][0-9.]*-r[0-9]+\.apk$/)) {
		printf "cannot parse <name>-<version>-r<N>.apk from %s\n", path > "/dev/stderr"
		bad = 1; exit 1
	}
	name = substr(base, 1, RSTART - 1)
	ver = substr(base, RSTART + 1, RLENGTH - 5)
	if (ver !~ /^[0-9]+(\.[0-9]+)*-r[0-9]+$/) {
		printf "unsupported version %s in %s\n", ver, path > "/dev/stderr"
		bad = 1; exit 1
	}
	if (!(name in count)) order_seen[++names] = name
	k = ++count[name]
	file[name, k] = path
	version[name, k] = ver
}
END {
	if (bad) exit 1
	for (i = 1; i <= names; i++) {
		name = order_seen[i]
		# Selection sort, newest first: a name has a handful of versions.
		for (a = 1; a <= count[name] && a <= keep; a++) {
			best = a
			for (b = a + 1; b <= count[name]; b++)
				if (vercmp(version[name, b], version[name, best]) > 0) best = b
			if (best != a) {
				t = file[name, a]; file[name, a] = file[name, best]; file[name, best] = t
				t = version[name, a]; version[name, a] = version[name, best]; version[name, best] = t
			}
			print file[name, a]
		}
	}
}'
