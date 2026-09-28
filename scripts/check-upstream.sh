#!/usr/bin/env bash
# 上游 fanchmwrt/fanchmwrt HEAD 与本仓库 last-built sha 比对。
# 输出写入 $GITHUB_OUTPUT（本地直接运行时回显到 stdout）：sha=<...> changed=true|false
# 注意：本脚本只判断"上游有没有变"，不决定要不要构建——
#   push / workflow_dispatch 一律构建（配置变更也要出固件）；
#   schedule 只在上游变化时由 workflow 里的 dispatch-build job 转发一次 workflow_dispatch。
set -euo pipefail

UPSTREAM_REPO="fanchmwrt/fanchmwrt"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

BRANCH=$(curl -sf "https://api.github.com/repos/$UPSTREAM_REPO" | jq -r .default_branch)
SHA=$(curl -sf "https://api.github.com/repos/$UPSTREAM_REPO/commits/$BRANCH" | jq -r .sha)
echo "upstream $BRANCH HEAD: $SHA"

OLD=$(cat "$REPO_ROOT/upstream_sha" 2>/dev/null || true)
echo "last built sha: ${OLD:-<none>}"
echo "sha=$SHA" >> "$OUT"

if [ "$OLD" = "$SHA" ]; then
  echo "upstream unchanged"
  echo "changed=false" >> "$OUT"
else
  echo "upstream changed"
  echo "changed=true" >> "$OUT"
fi
