#!/usr/bin/env bash
# 把上游 SRunPy 的 apk/ipk 附到本次产物目录（固件内已内置同源包，这里是给
# 其它机器侧载用的）。随后重算 images/ 全目录 sha256（覆盖 OpenWrt 自带的
# sha256sums，使其覆盖 srunpy 文件）。用法: fetch-srunpy-artifacts.sh <openwrt-dir>
set -euo pipefail

DEST="$1/bin/targets/x86_64/images"
[ -d "$DEST" ] || DEST="$1/bin/targets/x86/64/images"
mkdir -p "$DEST"

BASE="https://github.com/HofNature/SRunPy-OpenWRT/releases/download/v1.0.1"
for f in srunpy-1.0.1-r1.apk luci-app-srunpy-1.0.0-r1.apk srunpy-1.0.1.ipk luci-app-srunpy-1.0.0.ipk; do
  curl -fsSL -o "$DEST/$f" "$BASE/$f"
  echo "got $DEST/$f ($(wc -c < "$DEST/$f") bytes)"
done

cd "$DEST"
sha256sum ./* > sha256sums.txt
