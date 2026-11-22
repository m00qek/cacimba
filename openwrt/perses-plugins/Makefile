include $(TOPDIR)/rules.mk

# The plugins of Perses beyond the four the perses package comes with, each
# its own package: a router installs the ones its dashboards use, as each
# unpacks to ~11MB. Upstream releases each
# plugin on its own (github.com/perses/plugins, tag <id>/v<version>); these
# are the versions Perses PKG_VERSION bundles.
PKG_NAME:=perses-plugins
PKG_VERSION:=0.55.1
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

# Installing or removing a plugin changes what Perses loads: restart it if
# it is running, and never into an image being built (IPKG_INSTROOT). On
# every install, not only upgrades: Perses loads plugins when it starts.
define PersesPlugin/restart
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/perses ] &&
	/etc/init.d/perses running; then
	/etc/init.d/perses restart
fi
exit 0
endef

# PersesPlugin NAME,ID,VERSION,SHA256,WHAT: the package perses-plugin-ID,
# upstream's archive NAME-VERSION.tar.gz where the perses service points
# Perses at, under the name Perses expects. WHAT has no commas.
define PersesPlugin
  define Download/perses-plugin-$(2)
    URL:=https://github.com/perses/plugins/releases/download/$(2)/v$(3)/
    URL_FILE:=$(1)-$(3).tar.gz
    FILE:=perses-plugin-$(1)-$(3).tar.gz
    HASH:=$(4)
  endef
  $$(eval $$(call Download,perses-plugin-$(2)))

  define Package/perses-plugin-$(2)
    SECTION:=utils
    CATEGORY:=Utilities
    SUBMENU:=Perses plugins
    TITLE:=Perses $(1) plugin: $(5)
    URL:=https://github.com/perses/plugins
    VERSION:=$(3)-r$(PKG_RELEASE)
    PKGARCH:=all
  endef

  define Package/perses-plugin-$(2)/description
    The Perses $(1) plugin, $(3): $(5).
  endef

  define Package/perses-plugin-$(2)/install
	$$(INSTALL_DIR) $$(1)/usr/share/perses/plugins-archive
	$$(INSTALL_DATA) $$(DL_DIR)/perses-plugin-$(1)-$(3).tar.gz \
		$$(1)/usr/share/perses/plugins-archive/$(1)-$(3).tar.gz
  endef

  Package/perses-plugin-$(2)/postinst = $$(PersesPlugin/restart)
  Package/perses-plugin-$(2)/postrm = $$(PersesPlugin/restart)

  $$(eval $$(call BuildPackage,perses-plugin-$(2)))
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

# Datasources and their queries.
$(eval $(call PersesPlugin,Prometheus,prometheus,0.59.1,d23c335fa726d0eb41179d45ee825dafc1f6e93d869d7e7f708f16d880aef42c,Prometheus and VictoriaMetrics datasource and queries))
$(eval $(call PersesPlugin,VictoriaLogs,victorialogs,0.5.1,136af9c9eb3cf3bba8c0dcf4e7def2006e739e24349e639fe1c885658be8a8a6,VictoriaLogs datasource and log queries))

# Panels. The perses package itself has the time series and Markdown
# panels and both variable plugins (PERSES_BUILTIN), so they are not here.
$(eval $(call PersesPlugin,StatChart,statchart,0.15.1,17b570bffced8f305a181a2163fbd70e789090c102c76cc69aabd582fcf51ad7,single-value stat panels))
$(eval $(call PersesPlugin,GaugeChart,gaugechart,0.14.1,81ac65519116a8b8bed7fe24a251538a041342c5027e4ac2af986fa86c6f5756,gauge panels))
$(eval $(call PersesPlugin,BarChart,barchart,0.14.1,1fca5502fe6c32e52ef8f975e24ea91801bcdb4a9dd7ac62970bc9c847ad6e7f,bar charts))
$(eval $(call PersesPlugin,PieChart,piechart,0.15.1,6f551dae85d66c728be9aae9e5396ef3e7c672f668c2e83aa604e27c3d8d7536,pie charts))
$(eval $(call PersesPlugin,Table,table,0.14.1,e7321cd4962da82efd75593bb46307a938286f7fa7ca19304d867bd11bf1acce,table panels))
$(eval $(call PersesPlugin,TimeSeriesTable,timeseriestable,0.13.1,b0c36aaba9bb3b19ba1acbfeaefe1520baaafdece5a0dc5d720b241614647995,time series as a table))
$(eval $(call PersesPlugin,LogsTable,logstable,0.4.1,b901f404f6f083ad6538ca959999fba8c47ade59232291343f8696b0c9ac8682,log lines as a table))
$(eval $(call PersesPlugin,StatusHistoryChart,statushistorychart,0.14.1,e3ce375a80e29b83b58930c418384052fc7fd37a9c0f04fe55662951f14b423d,status history panels))
$(eval $(call PersesPlugin,HeatMapChart,heatmapchart,0.6.1,0574ac635670edcbf44ee2cccf85faecef37506cf8531938e257684f66a27b16,heat maps))
$(eval $(call PersesPlugin,HistogramChart,histogramchart,0.13.1,bd7be694a950d9d88c1893799457129b372fa9921bfa40314281c50a7c418d4d,histograms))

# The Explore view for logs (option explorer).
$(eval $(call PersesPlugin,LogExplorer,logexplorer,0.2.1,91003c59080f8d92328b0ce456a7aca29f4b5896e6d2a132039013adb7a9828f,the Explore view for logs))
