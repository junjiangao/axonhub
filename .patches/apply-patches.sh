#!/usr/bin/env bash
#
# apply-patches.sh — 在同步上游后，将本地补丁重新应用到工作分支
#
# 用法: 在工作分支上执行
#   bash .patches/apply-patches.sh
#
set -euo pipefail

PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES=(
  "001-upstream-protocol-compat.patch"
  "002-local-changes.patch"
  "003-request-log-cache-hit-rate.patch"
  "004-channel-proxy-direct-by-default.patch"
  "005-responses-reasoning-delta-alias.patch"
  "006-codex-openai-model-envelope.patch"
)

echo ">>> 应用本地补丁到 $(git branch --show-current)..."
echo

# 预检查：确保所有声明的补丁文件都存在
MISSING=0
for PATCH in "${PATCHES[@]}"; do
  if [ ! -f "$PATCHES_DIR/$PATCH" ]; then
    echo "  [✗] 缺失: $PATCH"
    MISSING=$((MISSING + 1))
  fi
done
if [ "$MISSING" -gt 0 ]; then
  echo "  [!] 有 $MISSING 个补丁文件缺失，请检查 .patches/ 目录"
  exit 1
fi

REPO_ROOT="$(cd "$PATCHES_DIR/.." && pwd)"
if [ -f "$REPO_ROOT/docker-compose-local" ]; then
  cp -- "$REPO_ROOT/docker-compose-local" "$REPO_ROOT/docker-compose.override.yml"
  echo "  [✓] 已从 docker-compose-local 生成 docker-compose.override.yml"
fi

for PATCH in "${PATCHES[@]}"; do
  PATCH_FILE="$PATCHES_DIR/$PATCH"
  if [ ! -f "$PATCH_FILE" ]; then
    echo "  [!] 跳过: $PATCH (文件不存在)"
    continue
  fi

  echo "  [*] 应用: $PATCH"

  if git apply --check "$PATCH_FILE"; then
    git apply "$PATCH_FILE"
    echo "  [✓] 成功"
  else
    echo "  [✗] 补丁检查失败，已停止应用: $PATCH" >&2
    echo "      文件位于: $PATCH_FILE" >&2
    echo "      请修复补丁后，在干净工作区重新执行。" >&2
    exit 1
  fi
  echo
done

echo ">>> 所有补丁应用成功"
