include $(TOPDIR)/rules.mk

PKG_NAME:=dhcp-snooper
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
include $(INCLUDE_DIR)/package.mk

define Package/dhcp-snooper
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Passive DHCP hostname snooper for bypass gateways
  DEPENDS:=+libc
endef

define Package/dhcp-snooper/description
  Listens for broadcast DHCP packets on the LAN and learns MAC -> hostname
  mappings while another router serves the leases. Keeps
  /tmp/dhcp_snoop.leases in dnsmasq lease format so fwxd can resolve
  terminal hostnames in bypass mode. Harmless when the local DHCP server
  is enabled (the UDP/67 bind is then retried in the background).
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	cp -rf ./src/* $(PKG_BUILD_DIR)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/dhcp-snooper/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/dhcp-snooper $(1)/usr/bin/
	$(INSTALL_BIN) ./files/dhcp-snooper.init $(1)/etc/init.d/dhcp-snooper
	$(INSTALL_DATA) ./files/dhcp-snooper.config $(1)/etc/config/dhcp-snooper
endef

$(eval $(call BuildPackage,dhcp-snooper))
