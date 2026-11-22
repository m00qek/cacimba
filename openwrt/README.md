# The OpenWrt feed

An OpenWrt 25.12 (apk) package feed. The packages are listed in the
[top-level README](../README.md#packages); each one's directory here has a
README with its configuration.

## Adding the feed

```sh
wget -O /etc/apk/keys/cacimba.pem \
  https://m00qek.github.io/cacimba/openwrt/25.12/feed.pub.pem
. /etc/openwrt_release
echo "https://m00qek.github.io/cacimba/openwrt/25.12/$DISTRIB_ARCH/packages.adb" \
  >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add vmagent
```

The packages and indexes are signed; the key above is the one in
[`apk.pub`](../apk.pub). To build it into an image, put it in the image's
`/etc/apk/keys/` (ImageBuilder `FILES=`).

## Upgrading and rolling back

Upgrading a package restarts its service if it is running, so the
version installed is the version running.

The feed keeps the three newest versions of each package, so the two before
the current one can be installed by their URLs to roll back (perses, at
~26MB a version, keeps two). The index lists the newest only.

## How the feed is built

[`feed.json`](../feed.json) lists the OpenWrt releases, their architectures,
and each package with how it is built:

- `"build": "prebuilt"`: an upstream binary, built for each of the package's
  `"arches"`. The Makefile picks the upstream download for the SDK's CPU.
- `"build": "noarch"`: nothing architecture-specific, built once.

[`.github/workflows/feed.yml`](../.github/workflows/feed.yml) builds every
changed package in the OpenWrt SDK
([`scripts/build.sh`](../scripts/build.sh)), installs the x86_64 and noarch
builds in an OpenWrt rootfs container and runs the package's `test.sh`
([`scripts/test.sh`](../scripts/test.sh)), and, on `main`, signs, files and
indexes them on the `gh-pages` branch
([`scripts/publish.sh`](../scripts/publish.sh)). `gh-pages` is a single
commit, replaced on every publish, so old binaries do not pile up in its
history. A change to Markdown files alone builds nothing.

To build and test a package locally, with docker:

```sh
sh scripts/build.sh 25.12 openwrt/sdk:x86-64-25.12.6 x86_64 out vmagent
sh scripts/test.sh openwrt/rootfs:x86_64-25.12.6 out vmagent
```

## Adding a package

Every package is configured through UCI, `/etc/config/<name>`: its init
script turns the options into the program's flags, environment or own
configuration file at start, so there is one place to configure it, and
tools that manage UCI manage it too.

1. `openwrt/<name>/Makefile`: `PKG_SOURCE_URL` and `PKG_HASH` per CPU,
   copied from upstream's checksums, the install rules, and the `postinst`
   that restarts the service on upgrade.
2. `openwrt/<name>/files/`: its procd init script (validated options, its
   own user, a ujail) and its UCI defaults, listed in `conffiles`.
3. `openwrt/<name>/test.sh`: what can be checked without procd.
4. `openwrt/<name>/README.md`: what it is, its options with their defaults,
   where it keeps its data, and what its jail sees.
5. An entry in `feed.json`, and a row in the
   [packages table](../README.md#packages).

The publish signs with the repository secret `APK_FEED_SIGNING_KEY`, the
private half of `apk.pub`, an EC P-256 key:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out apk.key
openssl ec -in apk.key -pubout -out apk.pub     # committed
gh secret set APK_FEED_SIGNING_KEY < apk.key && shred -u apk.key
```
