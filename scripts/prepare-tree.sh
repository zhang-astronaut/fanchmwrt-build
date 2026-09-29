#!/usr/bin/env bash
# 在 freshly cloned 的 openwrt 树上叠加本仓库的全部定制。用法: prepare-tree.sh <openwrt-dir>
#   1. 追加第三方 feeds（easytier / istore）
#   2. clone 第三方包：UA3F、EQoS、diskman（并修正各自的打包依赖问题）
#   3. UA3F 开机竞态修复（respawn 无限重试）——应用后强校验，失败即中止构建
#   4. fwx 流量统计 TPROXY 补丁（应用失败仅告警不阻断，详见 README）
#   5. 合并 Chelsio 内核配置片段（按符号去重后追加，兼容 config-6.x 文件名变化）
#   6. 拷贝 package/ 下的本地包（约定：目录名 = 包名）
#   7. 拷贝 files/ rootfs overlay（uci-defaults 等），应用后断言关键内容
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OW="$1"
cd "$OW"

# --- 1. feeds ---
cat >> feeds.conf.default <<'EOF'
src-git easytier https://github.com/EasyTier/luci-app-easytier.git;main
src-git istore https://github.com/linkease/istore.git;main
EOF

# --- 2. 第三方包 ---
# EQoS：官方 luci feed 没有；依赖 +tc 在本树无 kconfig 符号（tc-tiny 才有），不改会被静默裁剪
git clone --depth 1 https://github.com/Huangjoe123/luci-app-eqos.git package/luci-app-eqos
sed -i 's/+tc /+tc-tiny /' package/luci-app-eqos/Makefile

# Disk Manager（sbwml）：仓库根目录是文档，真正的包在子目录里
git clone --depth 1 https://github.com/sbwml/luci-app-diskman.git package/.diskman-src
mv package/.diskman-src/luci-app-diskman package/luci-app-diskman
rm -rf package/.diskman-src

# UA3F 官方源码直接作为 package（含 LuCI 界面）
git clone --depth 1 https://github.com/SunBK201/UA3F.git package/UA3F
# Build/Prepare 阶段要调 po2lmo（luci-base/host 提供），显式声明构建顺序
sed -i 's/^PKG_BUILD_DEPENDS:=golang\/host$/PKG_BUILD_DEPENDS:=golang\/host luci-base\/host/' \
  package/UA3F/openwrt/Makefile

# --- 2b. 运行时 apk 源裁剪（2026-09-29 实测：缺失会让路由器 apk update / iStore 刷源报错） ---
# base-files 生成 /etc/apk/repositories.d/distfeeds.list 时把 feeds.conf.default 里的
# 每个 feed 名都拼到官方发布仓库 URL（%U/packages/%A/<feed>）下；easytier/istore 是
# 第三方源，官方仓库没有对应目录 → 运行时必报 wget error 8（404）。
# 上游对自家 feed 已有先例（sed '/fanchmwrt/d'），此处按同一约定一并剔除；
# iStore 的运行时源由 luci-app-store 自带的 compat.list 提供，不受影响。
sed -i "s|sed -i '/fanchmwrt/d' \$(1)/etc/apk/repositories.d/distfeeds.list|sed -i -e '/fanchmwrt/d' -e '/easytier/d' -e '/istore/d' \$(1)/etc/apk/repositories.d/distfeeds.list|" \
  package/base-files/Makefile
grep -q "'/easytier/d'" package/base-files/Makefile || {
  echo "ERROR: distfeeds third-party feed prune failed to apply (upstream base-files/Makefile changed?)" >&2
  exit 1
}

# --- 3. UA3F 开机竞态修复（优先级最高的需求，必须应用成功才允许出镜像） ---
# 根因：开机时 WAN 默认路由未就绪 → BPF TC "no eligible interfaces" → 连续崩溃后
# procd 默认只重试 5 次即放弃 → 裸 UA 出网触发校园网封禁。
# respawn 第三参数 0 = 无限重试，等路由就绪后自动恢复。
sed -i 's/^    procd_set_param respawn$/    procd_set_param respawn 3600 5 0/' \
  package/UA3F/openwrt/files/ua3f.init
grep -n 'procd_set_param respawn' package/UA3F/openwrt/files/ua3f.init
grep -q 'procd_set_param respawn 3600 5 0' package/UA3F/openwrt/files/ua3f.init || {
  echo "ERROR: UA3F respawn fix failed to apply (upstream ua3f.init changed?)" >&2
  exit 1
}

# --- 4. fwx 流量统计 TPROXY 补丁：统计点 FORWARD → PRE/POST_ROUTING，TPROXY 流量不漏计 ---
# 上游 fwx 代码若已变动导致补丁失配，降级为告警继续（该补丁只影响流量统计精度，不影响 UA 改写）
PATCH="$REPO_ROOT/fwx-tproxy-stat.patch"
if git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH"
  echo "fwx-tproxy-stat.patch applied"
elif patch -p1 --forward < "$PATCH" >/dev/null 2>&1; then
  echo "::warning::fwx-tproxy-stat.patch applied via patch(1) with fuzz"
else
  echo "::warning::fwx-tproxy-stat.patch no longer applies (upstream fwx changed); continuing without it"
fi

# --- 5. Chelsio 内核配置片段合并（去重，避免裸 cat >> 产生重复符号定义） ---
KCFG=$(ls target/linux/x86/config-* 2>/dev/null | head -n1)
[ -n "$KCFG" ] || { echo "ERROR: target/linux/x86/config-* not found" >&2; exit 1; }
echo "merging Chelsio fragment into $KCFG"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  sym=$(printf '%s\n' "$line" | sed -n \
    -e 's/^\(CONFIG_[A-Za-z0-9_]*\)=.*/\1/p' \
    -e 's/^# \(CONFIG_[A-Za-z0-9_]*\) is not set$/\1/p')
  [ -n "$sym" ] && sed -i "/^$sym=/d;/^# $sym is not set$/d" "$KCFG"
  printf '%s\n' "$line" >> "$KCFG"
done < "$REPO_ROOT/package/kmod-cxgb4/kernel-config"

# --- 6. 本地包（目录名 = 包名，直接覆盖同名上游包） ---
for d in "$REPO_ROOT"/package/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  rm -rf "package/$name"
  cp -a "$d" "package/"
done

# --- 7. files/ rootfs overlay（uci-defaults 等；构建系统原生把树根 files/ 合入 rootfs） ---
if [ -d "$REPO_ROOT/files" ]; then
  mkdir -p "$OW/files"
  cp -a "$REPO_ROOT/files/." "$OW/files/"
  UDEF="$OW/files/etc/uci-defaults/99-fwx-filter-aaaa"
  HOOK="$OW/files/etc/hotplug.d/iface/99-fwx-filter-aaaa"
  [ -f "$UDEF" ] || { echo "ERROR: files overlay copy failed ($UDEF missing)" >&2; exit 1; }
  grep -q "filter_aaaa='1'" "$UDEF" || { echo "ERROR: $UDEF 关键内容丢失（filter_aaaa 断言失效）" >&2; exit 1; }
  [ -f "$HOOK" ] || { echo "ERROR: files overlay copy failed ($HOOK missing)" >&2; exit 1; }
  grep -q "allow_aaaa" "$HOOK" || { echo "ERROR: $HOOK 关键内容丢失（动态纠偏断言失效）" >&2; exit 1; }
  echo "files/ overlay copied"
fi

echo "prepare-tree: done"
