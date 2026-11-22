#!/bin/sh
# Smoke test, run by scripts/test.sh in an OpenWrt rootfs with every
# perses-plugin-* package installed (perses itself is tested with its own
# builtin plugins): each one's archive is where the perses service points
# Perses at, named NAME-VERSION.tar.gz, and is a plugin.
set -eu

fail() { echo "perses-plugins test: $*" >&2; exit 1; }

dir=/usr/share/perses/plugins-archive
count=0
for pkg in $(apk info 2>/dev/null | grep '^perses-plugin-'); do
	files=$(apk info -L "$pkg" | grep "^${dir#/}/" || true)
	[ "$(echo "$files" | grep -c .)" = 1 ] || fail "$pkg: not one archive in $dir: $files"
	f=/$files
	case "$(basename "$f")" in
		[A-Z]*-[0-9]*.tar.gz) ;;
		*) fail "$pkg: $(basename "$f") is not NAME-VERSION.tar.gz" ;;
	esac
	tar -tzf "$f" | grep -qx 'package.json\|./package.json' || fail "$pkg: $f has no package.json"
	count=$((count + 1))
done
[ "$count" -gt 0 ] || fail "no perses-plugin-* package installed"

# None is one perses ships itself.
for p in DatasourceVariable StaticListVariable TimeSeriesChart Markdown; do
	ls "$dir/$p"-* >/dev/null 2>&1 && fail "$p is a perses builtin, not a plugin package"
done

echo "perses-plugins: ok ($count plugins)"
