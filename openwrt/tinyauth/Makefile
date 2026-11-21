include $(TOPDIR)/rules.mk

PKG_NAME:=tinyauth
PKG_VERSION:=5.2.0
PKG_RELEASE:=1

# Upstream's own release build: a bare binary per CPU, named without its
# version, so it is saved under a name that has one. Both aarch64 package
# architectures run the arm64 one.
ifeq ($(ARCH),aarch64)
  TA_ARCH:=arm64
  PKG_HASH:=373ff8eb72e437925f9222953767612e13bb5da71173af16ab91c562cc7abd18
else ifeq ($(ARCH),x86_64)
  TA_ARCH:=amd64
  PKG_HASH:=a8c3d9e847e275f105bf74791ad9a733f76dcf890038381aeb7ab78ec50fc474
endif

PKG_SOURCE:=tinyauth-$(TA_ARCH)-v$(PKG_VERSION)
PKG_SOURCE_URL:=https://github.com/tinyauthapp/tinyauth/releases/download/v$(PKG_VERSION)/
PKG_SOURCE_URL_FILE:=tinyauth-$(TA_ARCH)
PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

# A static Go binary, as upstream built it: nothing to strip or relink.
STRIP:=:
RSTRIP:=:

define Package/tinyauth
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Tinyauth: forward-auth login in front of web apps
  URL:=https://tinyauth.app
  DEPENDS:=@(aarch64||x86_64) +ca-bundle +procd-ujail
  USERID:=tinyauth:tinyauth
endef

define Package/tinyauth/description
  Tinyauth puts a login page (local users, OAuth/OIDC providers or LDAP) in
  front of web apps behind a reverse proxy that supports forward auth, such
  as nginx's auth_request. Runs as a procd service configured in
  /etc/config/tinyauth; secret files go in /etc/tinyauth.
endef

define Package/tinyauth/conffiles
/etc/config/tinyauth
endef

# An upgrade replaces the files, not the running process: restart it, so
# the version installed is the version running. Only if it is running, and
# never into an image being built (IPKG_INSTROOT).
define Package/tinyauth/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ "$${PKG_UPGRADE}" = 1 ] &&
	/etc/init.d/tinyauth running; then
	/etc/init.d/tinyauth restart
fi
exit 0
endef

# The download is the binary itself.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR)/tinyauth
endef

define Build/Compile
endef

define Package/tinyauth/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tinyauth $(1)/usr/bin/tinyauth
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/tinyauth.init $(1)/etc/init.d/tinyauth
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/tinyauth.config $(1)/etc/config/tinyauth
	$(INSTALL_DIR) $(1)/etc/tinyauth
endef

$(eval $(call BuildPackage,tinyauth))
