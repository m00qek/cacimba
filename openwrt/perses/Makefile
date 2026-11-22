include $(TOPDIR)/rules.mk

PKG_NAME:=perses
PKG_VERSION:=0.55.1
PKG_RELEASE:=2

# Upstream's release build: a tarball per CPU holding the server, percli and
# the plugins it bundles. Only the server is packaged; each plugin is its own
# package (perses-plugins), so a router carries the ones it uses. Both
# aarch64 package architectures run the arm64 build.
ifeq ($(ARCH),aarch64)
  PERSES_ARCH:=arm64
  PKG_HASH:=bd777b183622e2eaeda6645748be47d65afb67eb91aa8d8d726a7c10efd8a1c5
else ifeq ($(ARCH),x86_64)
  PERSES_ARCH:=amd64
  PKG_HASH:=7c38ace5ce665e22d7d4f823b8bc0c8e91f9bcef381f218d8c564e0fe62ba750
endif

PKG_SOURCE:=perses_$(PKG_VERSION)_linux_$(PERSES_ARCH).tar.gz
PKG_SOURCE_URL:=https://github.com/perses/perses/releases/download/v$(PKG_VERSION)/
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

# A static Go binary, as upstream built it: nothing to strip or relink.
STRIP:=:
RSTRIP:=:

define Package/perses
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Perses: dashboards for Prometheus and VictoriaMetrics data
  URL:=https://perses.dev
  DEPENDS:=@(aarch64||x86_64) +ca-bundle +procd-ujail
  USERID:=perses:perses
endef

define Package/perses/description
  Perses is a dashboard server: dashboards, datasources and permissions are
  resources it can load from files, so they can live in version control.
  Runs as a procd service configured in /etc/config/perses. Its panels,
  queries and variables are plugins: it comes with the datasource and
  static list variables and the time series and Markdown panels; every
  other plugin is a perses-plugin-* package.
endef

define Package/perses/conffiles
/etc/config/perses
endef

# An upgrade replaces the files, not the running process: restart it, so
# the version installed is the version running. Only if it is running, and
# never into an image being built (IPKG_INSTROOT).
define Package/perses/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ "$${PKG_UPGRADE}" = 1 ] &&
	/etc/init.d/perses running; then
	/etc/init.d/perses restart
fi
exit 0
endef

# The plugins it ships with, from the tarball: Perses accepts no dashboard
# without a variable plugin and a panel plugin, so these make it usable
# alone. Every other plugin is a perses-plugin-* package (perses-plugins),
# never one of these.
PERSES_BUILTIN:= \
	DatasourceVariable-0.7.1 \
	StaticListVariable-0.10.1 \
	TimeSeriesChart-0.14.1 \
	Markdown-0.13.1

# Only the server and those plugins, out of the 150MB tarball.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) perses LICENSE \
		$(foreach p,$(PERSES_BUILTIN),plugins-archive/$(p).tar.gz)
endef

define Build/Compile
endef

define Package/perses/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/perses $(1)/usr/bin/perses
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/perses.init $(1)/etc/init.d/perses
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/perses.config $(1)/etc/config/perses
	$(INSTALL_DIR) $(1)/etc/perses/provisioning
	$(INSTALL_DIR) $(1)/usr/share/perses/plugins-archive
	$(INSTALL_DATA) $(foreach p,$(PERSES_BUILTIN),$(PKG_BUILD_DIR)/plugins-archive/$(p).tar.gz) \
		$(1)/usr/share/perses/plugins-archive/
	# Its encryption key and secret files are made on the router, not
	# shipped: keep them across a sysupgrade.
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	echo /etc/perses/ > $(1)/lib/upgrade/keep.d/perses
endef

$(eval $(call BuildPackage,perses))
