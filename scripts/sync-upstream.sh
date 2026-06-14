#!/usr/bin/env bash
#
# sync-upstream.sh — 同步上游 unstable，从 axonhub-patches 取补丁并应用
#
# 用法:
#   ./scripts/sync-upstream.sh          # 标准同步
#   ./scripts/sync-upstream.sh --dry    # 试运行
#
set -euo pipefail

UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="unstable"
MAIN_BRANCH="main"
PATCHES_BRANCH="axonhub-patches"
PATCHES_DIR=".patches"
SCRIPTS_DIR="scripts"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry) DRY_RUN=true ;;
  esac
done

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY] $*"
  else
    echo "  [RUN] $*"
    "$@"
  fi
}

echo "============================================"
echo "  AxonHub 上游同步脚本"
echo "  分支: $MAIN_BRANCH ← $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
echo "  日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo

if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
  echo "[!] 未找到 upstream remote，请先添加:"
  echo "    git remote add upstream git@github.com:looplj/axonhub.git"
  exit 1
fi

# Step 1: 同步 unstable
echo ">>> [1/5] 同步 $UPSTREAM_BRANCH 到最新上游..."
run git checkout "$UPSTREAM_BRANCH"
run git pull "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
run git push origin "$UPSTREAM_BRANCH"
echo

# Step 2: 重置 main 到 unstable
echo ">>> [2/5] 重置 $MAIN_BRANCH 到 $UPSTREAM_BRANCH..."
run git checkout "$MAIN_BRANCH"
run git reset --hard "$UPSTREAM_BRANCH"
echo

# Step 3: 从 axonhub-patches 拉取补丁和相关文件
echo ">>> [3/5] 从 $PATCHES_BRANCH 拉取补丁..."
run git checkout "$PATCHES_BRANCH" -- "$PATCHES_DIR/" "$SCRIPTS_DIR/" .gitignore
echo

# Step 4: 应用本地补丁
echo ">>> [4/5] 应用本地补丁..."
run bash "$PATCHES_DIR/apply-patches.sh"
echo

# Step 5: 提交并推送
MSG="chore: sync upstream $(date '+%Y%m%d')"
echo ">>> [5/5] 提交并推送到 origin..."
run git add -A
run git commit -m "$MSG"
run git push origin "$MAIN_BRANCH" --force-with-lease
echo

echo "============================================"
echo "  同步完成"
echo "  $MAIN_BRANCH: $(git rev-parse --short HEAD)"
echo "============================================"
