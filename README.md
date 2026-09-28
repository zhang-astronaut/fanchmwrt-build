# FanchmWrt 定制固件（fanchmwrt-build）

基于上游 [fanchmwrt/fanchmwrt](https://github.com/fanchmwrt/fanchmwrt)（OpenWrt 25.12 衍生，x86_64，内核 6.12.x）
自动编译的定制固件。目标设备：J5005 软路由（日常在线），也可给 VM 客人机使用。

> 本仓库是 `zhang-astronaut/fanchmwrt-ci` 的干净重建：内容以旧仓库 r104
> （路由器实机验证通过的最后一个版本）及其后已整理的改动为基线，重构了 CI 结构。
> `package/user-sessiond-ct` 与 2026-09-28 路由器上实际运行的版本逐字节一致。
> Release 版本号在新仓库从 **r1** 重新计数（旧仓库止于 r104）。

## 固件特性

### 校园网 / 代理
- **UA3F（最高优先级）**：TPROXY 全局 User-Agent 改写为 `FFF`（端口 1080，含 LuCI 界面）。
  内置**开机竞态修复**：原版 procd respawn 只重试 5 次，WAN 默认路由未就绪时 BPF TC
  连续失败后被永久放弃（校园网裸 UA 封禁的根因）；已改为 `respawn 3600 5 0` 无限重试。
  CI 中该修复**应用后强校验，失配即构建失败**（见 `scripts/prepare-tree.sh`）。
  验证：`http://ua.233996.xyz/` 服务器侧 UA 应为 `FFF`。
- **SRunPy 校园网自动登录**（深澜）：`srunpy` + `luci-app-srunpy` + `python3-requests`，
  源自 [HofNature/SRunPy-OpenWRT](https://github.com/HofNature/SRunPy-OpenWRT)；
  Release 附上游 apk/ipk 便于其它机器侧载。

### 监控
- **用户会话统计（UA3F TPROXY 下可用）**：`package/user-sessiond-ct`。
  闭源 `fwx_user.ko` 在 TPROXY 下会话表为空，本包用 `/proc/net/arp` + `/proc/net/nf_conntrack`
  在用户态聚合每 MAC 会话数：后台采样器每 5s 原子写 `/tmp/user_session_hist.json`，
  LuCI 只读该文件并按时间窗分桶出曲线。关键坑（都已修，别回退）：
  ARP `flags=0x2` 是 complete 不能用 `flags%2` 过滤；`dhcp.leases` 首列是过期时间不是 MAC；
  LuCI 与采样器**禁止双写** hist 文件；5min/1h 曲线必须按各自 step 分桶。
- **fwx 流量统计 TPROXY 补丁**（`fwx-tproxy-stat.patch`）：统计点从 FORWARD 改到
  PRE/POST_ROUTING，TPROXY 流量不漏计。上游 fwx 变动导致补丁失配时 CI 仅告警不阻断。

### QoS / 网络硬件
- **SQM（主）**：`sqm-scripts` + LuCI（Cake / fq_codel，含 cake、fq-pie、ifb kmod）。
  使用 SQM 时请关闭「软件流量分载」，否则 tc 形同虚设。
- **EQoS（辅）**：`luci-app-eqos` + `tc-tiny`（[Huangjoe123/luci-app-eqos](https://github.com/Huangjoe123/luci-app-eqos)，
  CI 中把不可解析的 `+tc` 依赖改为 `tc-tiny`）。
- **Chelsio T520-CR 10G 网卡**：本地 KernelPackage `kmod-cxgb4`（目录名=包名），
  内核片段按符号去重合并进 `target/linux/x86/config-*`；T1/T3 老卡刻意排除。
- **磁盘管理**：`luci-app-diskman`（[sbwml](https://github.com/sbwml/luci-app-diskman)）+ 分区/文件系统工具链。

### 无线
- MT7922 USB（`kmod-mt7921u` + `kmod-mt7922-firmware`，USB ID `0489:e0d8`）
- MT7921 PCIe（客人机/VM：`kmod-mt7921e` + `kmod-mt7921-firmware`）
- 常用驱动：iwlwifi（ax200/ax201）、ath9k、rtw88-8822ce、rtw89-8852ae
- `wpad-mesh-mbedtls`（802.11s mesh + SAE，顶掉 basic 变体）

### 系统 / 工具
- **Docker** + `luci-app-dockerman`；**iStore 软件中心**（`luci-app-store`，
  CI 修正其不可解析的 `+tar` 依赖）；**EasyTier**；**SFTP**（`openssh-sftp-server` + dropbear SFTP）
- **FanchmWrt 应用中心**：`luci-app-fwx-app-center`
- rootfs 4G，首次开机自动扩容

## 已移除（终态，CI 断言守护）

以下包**禁止**进入镜像，`scripts/enforce-config.sh` 会对 `forbidden-packages.txt`
逐一断言，任何一个被依赖带进来都会让构建失败：

| 移除项 | 原因 |
|---|---|
| PassWall / PassWall2、xray-core、sing-box | 校园网环境不需要；tproxy 模式与 UA3F 抢 mangle/PREROUTING |
| `luci-app-qos` / `qos-scripts` | 与 SQM 重复 |
| Chelsio T1/T3（`kmod-cxgb`、`kmod-cxgb3` 等） | 上游无包且易触发 kconfig 交互挂死 |
| `kmod-ath10k-ct` | 与 `kmod-ath10k` 文件冲突 |
| `wpad-basic-*` / `wpad-mesh-openssl` | 与 `wpad-mesh-mbedtls` 冲突 |

> **若将来加回 PassWall（红线）**：TCP 代理方式必须保持 `redirect`，禁止 `tproxy`
> （与 UA3F 的 TPROXY 在 mangle PREROUTING 抢包）；数据流
> `LAN → UA3F(TPROXY 改 UA) → PassWall(redirect 加密) → WAN`；端口避开 UA3F 的 1080。

## 仓库结构

```
.github/workflows/build.yml   # CI：check（上游比对）+ build（编译/产物/Release）
scripts/
  check-upstream.sh           # 上游 sha 比对，决定是否跳过（仅 schedule 可跳过）
  prepare-tree.sh             # feeds / 第三方包 / UA3F respawn 修复 / fwx 补丁 / 内核片段合并
  enforce-config.sh           # defconfig + REQUIRED 回填断言 + FORBIDDEN 负向断言
  collect-images.sh           # 产物汇总 + vhd/vhdx 转换
  fetch-srunpy-artifacts.sh   # SRunPy apk/ipk 附加 + sha256 重算
  selfcheck.sh                # 本地/CI 自检（语法 / 清单 / LF）
required-packages.txt         # 必须进镜像的包（单一来源，增删包只改这里）
forbidden-packages.txt        # 禁止进镜像的包（终态守护）
fanchmwrt.config              # seed 配置（defconfig 展开后再由 REQUIRED 回填）
fwx-tproxy-stat.patch         # fwx 流量统计 TPROXY 补丁
upstream_sha                  # 上次成功编译的上游 commit（CI 自动维护）
package/
  user-sessiond-ct/           # 会话统计（采样器 + LuCI controller + user_sessiond）
  kmod-cxgb4/                 # Chelsio T520 KernelPackage + kernel-config 片段
  srunpy/  luci-app-srunpy/   # 校园网自动登录
docs/compose/spec/            # 设计记录（会话统计 / IO 优化）
```

约定：`package/` 下**目录名 = 包名**（OpenWrt 扫描要求，kmod 尤其敏感）；
所有文本文件 LF（`.gitattributes` 强制，selfcheck 校验）。

## CI 工作方式

- **触发**：push 到 main（`docs/**`、`README.md` 改动不触发）；每 6 小时检查上游
  fanchmwrt/fanchmwrt，无变化则跳过；`workflow_dispatch` 手动强制构建。
- **concurrency**：`firmware-build` 组 + `cancel-in-progress`，同一时间只有一个构建，
  不会像旧仓库那样排队堆积。
- **双重包断言**：REQUIRED 回填后 olddefconfig 固化再逐个校验（防 defconfig
  静默丢包——“编译绿了但镜像里没有包”的回归防线）；FORBIDDEN 反向校验终态。
- **产物**：squashfs/ext4 × UEFI/BIOS 镜像（img.gz + vhd + vhdx）+ manifest +
  sha256 + SRunPy apk/ipk，同时上传 artifact（14 天）并创建 Release（tag = r<run_number>）。
- 构建成功后 CI 自动提交 `chore: built upstream <sha>` 更新 `upstream_sha`（[skip ci] 不回环）。

## 本地开发

```sh
bash scripts/selfcheck.sh        # 改完仓库先跑：脚本语法 / 清单格式 / LF / 目录约定
```

- 增删固件包：改 `required-packages.txt`（必要时同步 `fanchmwrt.config` 删除对应 `=y` 行；
  移除包时优先加进 `forbidden-packages.txt` 防止依赖回带）。
- CI 脚本全部独立可读，本地 `bash -n scripts/<x>.sh` 可单测语法；
  各脚本头部注释写明用途与用法。

## 刷机后验收清单

1. UA3F：`http://ua.233996.xyz/` 显示 UA = `FFF`；`/etc/init.d/ua3f` 的 respawn 为 `3600 5 0`
2. 会话统计：`pgrep -af user-session-sampler` 在跑；下拉有主机名；5min/1h 曲线不同且多点；关页重开历史仍在
3. 关键包：`apk list --installed | grep -E 'ua3f|user-sessiond-ct|sqm|luci-app-diskman|kmod-cxgb4'`
4. QoS：LuCI 里 SQM/EQoS 可用（开 SQM 时关软件分载）
5. 磁盘：Disk Manager 可分区挂载
6. DHCP/DNS：客户端 DNS = `192.168.100.1`（路由器 dnsmasq → 国内上游）
7. 无 PassWall/xray/sing-box 残留

### 首次刷机后的一次性网络配置（uci，按需）

```sh
uci set dhcp.lan.start='100'; uci set dhcp.lan.limit='150'; uci set dhcp.lan.leasetime='12h'
uci -q delete dhcp.@dnsmasq[0].server
for s in 223.5.5.5 119.29.29.29 202.102.224.68 202.196.16.3; do uci add_list dhcp.@dnsmasq[0].server="$s"; done
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].domain='lan'; uci add_list dhcp.@dnsmasq[0].local='/lan/'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

（不要用 `192.168.100.3` / AdGuard Home / 飞牛，已弃用。）

## 相关链接

- 上游固件源码：<https://github.com/fanchmwrt/fanchmwrt>
- UA3F：<https://github.com/SunBK201/UA3F>
- SRunPy：<https://github.com/HofNature/SRunPy-OpenWRT>
- EasyTier LuCI：<https://github.com/EasyTier/luci-app-easytier>
- iStore：<https://github.com/linkease/istore>
- EQoS：<https://github.com/Huangjoe123/luci-app-eqos> ｜ Disk Manager：<https://github.com/sbwml/luci-app-diskman>
- 前身仓库（存档，勿再推送）：<https://github.com/zhang-astronaut/fanchmwrt-ci>
