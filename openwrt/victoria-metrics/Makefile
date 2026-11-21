include $(TOPDIR)/rules.mk

PKG_NAME:=victoria-metrics
PKG_VERSION:=1.156.0
PKG_RELEASE:=3

# Upstream's own release build, one tarball per CPU: both aarch64 package
# architectures run the arm64 one.
ifeq ($(ARCH),aarch64)
  VM_ARCH:=arm64
  PKG_HASH:=f777110b232bfdf435556c57d0896716e27000afafe969c4eb08852352dceb7d
else ifeq ($(ARCH),x86_64)
  VM_ARCH:=amd64
  PKG_HASH:=54409ea381db0316f0bf6f242c718bc498085eb1eb37520b73526e6d86891601
endif

PKG_SOURCE:=victoria-metrics-linux-$(VM_ARCH)-v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v$(PKG_VERSION)/
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

# A static Go binary, as upstream built it: nothing to strip or relink.
STRIP:=:
RSTRIP:=:

define Package/victoria-metrics
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=VictoriaMetrics: time series database
  URL:=https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/
  DEPENDS:=@(aarch64||x86_64) +procd-ujail
  USERID:=victoria-metrics:victoria-metrics
endef

define Package/victoria-metrics/description
  A single-node VictoriaMetrics: a time series database that accepts
  Prometheus remote-write and other ingestion protocols, and answers
  PromQL and MetricsQL queries. Runs as a procd service configured in
  /etc/config/victoria-metrics; it needs a data_dir on persistent storage.
endef

define Package/victoria-metrics/conffiles
/etc/config/victoria-metrics
endef

# An upgrade replaces the files, not the running process: restart it, so
# the version installed is the version running. Only if it is running, and
# never into an image being built (IPKG_INSTROOT).
define Package/victoria-metrics/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ "$${PKG_UPGRADE}" = 1 ] &&
	/etc/init.d/victoria-metrics running; then
	/etc/init.d/victoria-metrics restart
fi
exit 0
endef

# The tarball has no top directory: unpack it into the build directory.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) victoria-metrics-prod
endef

define Build/Compile
endef

define Package/victoria-metrics/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/victoria-metrics-prod $(1)/usr/bin/victoria-metrics
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/victoria-metrics.init $(1)/etc/init.d/victoria-metrics
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/victoria-metrics.config $(1)/etc/config/victoria-metrics
endef

$(eval $(call BuildPackage,victoria-metrics))
