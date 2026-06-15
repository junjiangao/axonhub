#!/usr/bin/env bash
#
# apply-patches.sh — 在同步上游后，将本地补丁重新应用到 main
#
# 用法: 在 main 分支上执行
#   bash .patches/apply-patches.sh
#
set -euo pipefail

PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES=(
  "000-gitignore.patch"
  "001-local-config.patch"
  "002-bugfixes.patch"
  "003-testdata.patch"
  "004-synthesize-stream-finish-reason.patch"
)

echo ">>> 应用本地补丁到 $(git branch --show-current)..."
echo

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
    echo "  [!] 冲突，尝试三次合并..."
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
