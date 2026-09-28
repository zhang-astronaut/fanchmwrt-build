#!/usr/bin/env bash
# 上游 fanchmwrt/fanchmwrt HEAD 与本仓库 last-built sha 比对。
# 仅 schedule 事件在上游无变化时跳过构建；push / workflow_dispatch 一律构建。
# 输出写入 $GITHUB_OUTPUT（本地直接运行时回显到 stdout）：sha=<...> build=true|false
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

if [ "$OLD" = "$SHA" ] && [ "${CI_EVENT:-push}" = "schedule" ]; then
  echo "no upstream update, skip build"
  echo "build=false" >> "$OUT"
else
  echo "build=true" >> "$OUT"
fi
