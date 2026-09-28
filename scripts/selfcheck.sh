#!/usr/bin/env bash
# 仓库自检：本地与 CI 均可运行（不需要 openwrt 树），改完仓库先跑这个。
#   - scripts/ 全部脚本 bash -n 语法检查
#   - package/ 每个目录有 Makefile（目录名 = 包名约定）
#   - required / forbidden 清单：每行一个包名、无重复、两清单无交集
#   - kernel-config 片段：LF 行尾、符号无重复
#   - 仓库文本文件无 CRLF（.gitattributes 兜底）
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"
fail=0

for f in scripts/*.sh; do
  if bash -n "$f"; then echo "  OK   $f"; else echo "  FAIL $f (syntax)" >&2; fail=1; fi
done

for d in package/*/; do
  if [ -f "$d/Makefile" ]; then echo "  OK   $d"; else echo "  FAIL $d (missing Makefile)" >&2; fail=1; fi
done

for list in required-packages.txt forbidden-packages.txt; do
  dup=$(grep -vE '^[[:space:]]*(#|$)' "$list" | sort | uniq -d)
  [ -z "$dup" ] || { echo "  FAIL $list duplicates: $dup" >&2; fail=1; }
  bad=$(grep -vE '^[[:space:]]*(#|$)' "$list" | grep -E '[[:space:]]' || true)
  [ -z "$bad" ] || { echo "  FAIL $list multi-token lines: $bad" >&2; fail=1; }
done

overlap=$(comm -12 \
  <(grep -vE '^[[:space:]]*(#|$)' required-packages.txt | sort) \
  <(grep -vE '^[[:space:]]*(#|$)' forbidden-packages.txt | sort))
[ -z "$overlap" ] || { echo "  FAIL required/forbidden overlap: $overlap" >&2; fail=1; }

kc="package/kmod-cxgb4/kernel-config"
if grep -q $'\r' "$kc"; then echo "  FAIL $kc has CRLF" >&2; fail=1; fi
dupsym=$(sed -n \
  -e 's/^\(CONFIG_[A-Za-z0-9_]*\)=.*/\1/p' \
  -e 's/^# \(CONFIG_[A-Za-z0-9_]*\) is not set$/\1/p' "$kc" | sort | uniq -d)
[ -z "$dupsym" ] || { echo "  FAIL $kc duplicate symbols: $dupsym" >&2; fail=1; }

# 用 awk 检测 CRLF：避免向 grep 传裸 CR 参数（MSYS 下有被吞成空模式的风险），
# 也顺带排除二进制文件
crlf=$(find . -path ./.git -prune -o \( -type f ! -name '*.img' ! -name '*.gz' \) -print0 2>/dev/null \
  | xargs -0 -r awk '/\r$/ { print FILENAME; nextfile }' 2>/dev/null | sort -u || true)
if [ -n "$crlf" ]; then echo "  FAIL CRLF found in: $crlf" >&2; fail=1; fi

[ "$fail" = 0 ] && echo "selfcheck: all good" || { echo "selfcheck failed" >&2; exit 1; }
