include $(TOPDIR)/rules.mk

PKG_NAME:=victoria-logs
PKG_VERSION:=1.54.0
PKG_RELEASE:=3

# Upstream's own release build, one tarball per CPU: both aarch64 package
# architectures run the arm64 one.
ifeq ($(ARCH),aarch64)
  VM_ARCH:=arm64
  PKG_HASH:=f6c4eb5bc4e2ec5a70c75f670f038122eed907b7e635b66497e80d38956561fa
else ifeq ($(ARCH),x86_64)
  VM_ARCH:=amd64
  PKG_HASH:=739e78c82294520b6079bc8a6ae32a1f9fb95a543092929a53a2fe9ab7383016
endif

PKG_SOURCE:=victoria-logs-linux-$(VM_ARCH)-v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/VictoriaMetrics/VictoriaLogs/releases/download/v$(PKG_VERSION)/
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

# A static Go binary, as upstream built it: nothing to strip or relink.
STRIP:=:
RSTRIP:=:

define Package/victoria-logs
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=VictoriaLogs: log database
  URL:=https://docs.victoriametrics.com/victorialogs/
  DEPENDS:=@(aarch64||x86_64) +procd-ujail
  USERID:=victoria-logs:victoria-logs
endef

define Package/victoria-logs/description
  A single-node VictoriaLogs: a log database that accepts syslog,
  Loki, Elasticsearch and JSON-lines ingestion, and answers LogsQL
  queries. Runs as a procd service configured in /etc/config/victoria-logs,
  with any syslog inputs as sections there; it needs a data_dir on
  persistent storage.
endef

define Package/victoria-logs/conffiles
/etc/config/victoria-logs
endef

# An upgrade replaces the files, not the running process: restart it, so
# the version installed is the version running. Only if it is running, and
# never into an image being built (IPKG_INSTROOT).
define Package/victoria-logs/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ "$${PKG_UPGRADE}" = 1 ] &&
	/etc/init.d/victoria-logs running; then
	/etc/init.d/victoria-logs restart
fi
exit 0
endef

# The tarball has no top directory: unpack it into the build directory.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) victoria-logs-prod
endef

define Build/Compile
endef

define Package/victoria-logs/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/victoria-logs-prod $(1)/usr/bin/victoria-logs
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/victoria-logs.init $(1)/etc/init.d/victoria-logs
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/victoria-logs.config $(1)/etc/config/victoria-logs
endef

$(eval $(call BuildPackage,victoria-logs))
