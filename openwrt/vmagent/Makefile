include $(TOPDIR)/rules.mk

PKG_NAME:=vmagent
PKG_VERSION:=1.156.0
PKG_RELEASE:=1

# Upstream's own release build, one tarball per CPU: both aarch64 package
# architectures run the arm64 one. The tarball holds every vmutils tool;
# only vmagent is packaged.
ifeq ($(ARCH),aarch64)
  VM_ARCH:=arm64
  PKG_HASH:=1a8e4ed55df2a59d5cd03056213f50d293d4fab029e38dd960597362d92cf176
else ifeq ($(ARCH),x86_64)
  VM_ARCH:=amd64
  PKG_HASH:=d71f7f00e07782531000620ec6c2a9d7ec83324f364dd1f36095ab378b5fb43b
endif

PKG_SOURCE:=vmutils-linux-$(VM_ARCH)-v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v$(PKG_VERSION)/
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

# A static Go binary, as upstream built it: nothing to strip or relink.
STRIP:=:
RSTRIP:=:

define Package/vmagent
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=VictoriaMetrics agent: scrape metrics and remote-write them
  URL:=https://docs.victoriametrics.com/victoriametrics/vmagent/
  DEPENDS:=@(aarch64||x86_64) +ca-bundle +procd-ujail
  USERID:=vmagent:vmagent
endef

define Package/vmagent/description
  vmagent scrapes Prometheus-format metrics and writes them to one or more
  Prometheus remote-write endpoints (VictoriaMetrics, Prometheus, Mimir, ...),
  queuing on disk for each endpoint while it is unreachable. Runs as a procd
  service configured in /etc/config/vmagent.
endef

define Package/vmagent/conffiles
/etc/config/vmagent
/etc/vmagent/scrape.yml
endef

# The tarball has no top directory: unpack it into the build directory.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) vmagent-prod
endef

define Build/Compile
endef

define Package/vmagent/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vmagent-prod $(1)/usr/bin/vmagent
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/vmagent.init $(1)/etc/init.d/vmagent
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/vmagent.config $(1)/etc/config/vmagent
	$(INSTALL_DIR) $(1)/etc/vmagent
	$(INSTALL_DATA) ./files/scrape.yml $(1)/etc/vmagent/scrape.yml
endef

$(eval $(call BuildPackage,vmagent))
