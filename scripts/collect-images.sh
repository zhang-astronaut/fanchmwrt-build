#!/usr/bin/env bash
# 收集固件产物：解包 combined 镜像并转换 VHD/VHDX（Hyper-V 用），
# 汇总 img.gz / manifest / sha256 到 images/ 目录（artifacts 与 Release 都从这里取）。
# 用法: collect-images.sh <openwrt-dir>
set -euo pipefail

cd "$1/bin/targets/x86/64"
mkdir -p images
for img in *-combined-*.img.gz; do
  [ -e "$img" ] || continue
  base=$(basename "$img" .img.gz)
  gunzip -c "$img" > "images/$base.img"
  qemu-img convert -O vhdx "images/$base.img" "images/$base.vhdx"
  qemu-img convert -O vpc "images/$base.img" "images/$base.vhd"
  rm -f "images/$base.img"
done
cp ./*.img.gz images/ 2>/dev/null || true
cp ./*.manifest images/ 2>/dev/null || true
cp sha256sums images/ 2>/dev/null || true
ls -la images/
