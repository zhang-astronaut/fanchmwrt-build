#!/usr/bin/env bash
# 生成最终 .config 并锁定包集合。用法: enforce-config.sh <openwrt-dir>
#   1. feeds 安装后修正 iStore luci-app-store 的 +tar 依赖
#   2. make defconfig 展开 seed 配置
#   3. 按 required-packages.txt 回填 =y，olddefconfig 固化
#   4. 断言 REQUIRED 全部 =y —— 防 defconfig 静默丢包（2026-09-13 曾因此
#      出过"编译成功但镜像里没有 PassWall2"的绿皮事故，此处为回归防线）
#   5. 断言 FORBIDDEN 全部未启用 —— 守住"已移除"终态（PassWall/xray/...）
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$1"

# iStore：luci-app-store 依赖 +tar，本树没有 CONFIG_PACKAGE_tar 符号（busybox 提供 tar），
# 不去掉这个依赖整包会被 defconfig 静默裁剪
if [ -f feeds/istore/luci/luci-app-store/Makefile ]; then
  sed -i 's/ +tar / /; s/+tar //' feeds/istore/luci/luci-app-store/Makefile
fi

cp "$REPO_ROOT/fanchmwrt.config" .config
make defconfig

REQUIRED=$(grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/required-packages.txt")
FORBIDDEN=$(grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/forbidden-packages.txt")

for s in $REQUIRED; do
  sed -i "/^# CONFIG_PACKAGE_${s} is not set$/d" .config
  grep -q "^CONFIG_PACKAGE_${s}=y$" .config || echo "CONFIG_PACKAGE_${s}=y" >> .config
done
./scripts/config/conf --olddefconfig Config.in

fail=0
for s in $REQUIRED; do
  if grep -q "^CONFIG_PACKAGE_${s}=y$" .config; then
    echo "  OK   $s"
  else
    echo "  FAIL $s (dropped by defconfig / missing in tree)" >&2
    fail=1
  fi
done
for s in $FORBIDDEN; do
  if grep -q "^CONFIG_PACKAGE_${s}=y$" .config; then
    echo "  FORBIDDEN-BUT-PRESENT $s" >&2
    fail=1
  fi
done

if [ "$fail" != 0 ]; then
  echo "package set enforcement failed, aborting build" >&2
  exit 1
fi
echo "enforce-config: package set verified ($(echo $REQUIRED | wc -w) required, $(echo $FORBIDDEN | wc -w) forbidden)"
