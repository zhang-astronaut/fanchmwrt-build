# Chelsio T520-CR（T4/T5/T6）独立 KernelPackage。
#
# 关键：独立目录的 in-tree kmod 必须 1:1 复刻 package/kernel/linux 外壳的模式，
# 否则会落进普通用户态包的构建流程（默认 make -C PKG_BUILD_DIR → "No makefile found"）：
#   1) 必须有 PKG_NAME（否则 kernel.mk 的 PKG_BUILD_DIR 默认值展开为 linux-x86_64//）
#   2) 必须 override Build/Prepare/Configure/Compile 为空（.ko 由内核本体编译产生，
#      本包只负责在 install 阶段收集 LINUX_DIR 下的 cxgb4.ko）
#   3) 构建期必须 -include $(LINUX_DIR)/.config（把 CONFIG_CHELSIO_T4=m 导入为 make
#      变量，KernelPackage 宏据此选择真正的 install 规则而非"空包"分支）
# 见 include/kernel.mk 的 KernelPackage 宏与 package/kernel/linux/Makefile。

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=cxgb4
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

ifeq ($(DUMP),)
  -include $(LINUX_DIR)/.config
endif

define KernelPackage/cxgb4
  SUBMENU:=Network Devices
  TITLE:=Chelsio T4/T5/T6 10/25/40/100GbE (T520-CR)
  DEPENDS:=@PCI_SUPPORT
  KCONFIG:=CONFIG_CHELSIO_T4
  FILES:=$(LINUX_DIR)/drivers/net/ethernet/chelsio/cxgb4/cxgb4.ko
  AUTOLOAD:=$(call AutoLoad,33,cxgb4)
endef

define KernelPackage/cxgb4/description
  Driver for Chelsio T4/T5/T6 adapters such as T520-CR.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call KernelPackage,cxgb4))
