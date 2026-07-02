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
  "000-panic-recover-stack-trace.patch"
  "001-finishreason-empty-string-compat.patch"
  "002-openai-inbound-stream-finish-reason.patch"
  "003-fix-stream-completed-on-finish-reason.patch"
  "004-local-changes.patch"
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

for PATCH in "${PATCHES[@]}"; do
  PATCH_FILE="$PATCHES_DIR/$PATCH"
  if [ ! -f "$PATCH_FILE" ]; then
    echo "  [!] 跳过: $PATCH (文件不存在)"
    continue
  fi

  echo "  [*] 应用: $PATCH"

  if git apply --check "$PATCH_FILE" 2>/dev/null; then
    git apply "$PATCH_FILE"
    echo "  [✓] 成功"
  else
    echo "  [!] 冲突，尝试 --reject 强制应用..."
    if git apply --reject "$PATCH_FILE" 2>/dev/null; then
      echo "  [~] 部分应用，请检查 .rej 文件并手动修复"
    else
      echo "  [✗] 应用失败，请手动处理: $PATCH"
      echo "      文件位于: $PATCH_FILE"
    fi
  fi
  echo
done

echo ">>> 补丁应用完成"
echo "    如果有 .rej 文件残留，请手动解决冲突"
