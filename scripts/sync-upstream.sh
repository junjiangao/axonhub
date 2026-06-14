#!/usr/bin/env bash
#
# sync-upstream.sh — 同步上游 unstable，生成本地工作分支并应用补丁
#
# 用法:
#   ./scripts/sync-upstream.sh                    # 生成 work-YYYYMMDD
#   ./scripts/sync-upstream.sh work/my-feature    # 指定工作分支名
#   ./scripts/sync-upstream.sh --dry              # 试运行
#
set -euo pipefail

UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="unstable"
PATCHES_BRANCH="main"
DRY_RUN=false
WORK_BRANCH=""

for arg in "$@"; do
  case "$arg" in
    --dry) DRY_RUN=true ;;
    -*)
      echo "[!] 未知选项: $arg"
      echo "用法: $0 [分支名] [--dry]"
      exit 1
      ;;
    *)
      if [ -z "$WORK_BRANCH" ]; then
        WORK_BRANCH="$arg"
      fi
      ;;
  esac
done

# 工作分支名：优先用参数，否则自动生成
WORK_BRANCH="${WORK_BRANCH:-work-$(date '+%Y%m%d')}"

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY] $*"
  else
    echo "  [RUN] $*"
    "$@"
  fi
}

echo "============================================"
echo "  AxonHub 同步脚本"
echo "  上游: $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
echo "  补丁: $PATCHES_BRANCH 分支"
echo "  工  作分支: $WORK_BRANCH"
echo "  日期: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo

if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
  echo "[!] 未找到 upstream remote，请先添加:"
  echo "    git remote add upstream git@github.com:looplj/axonhub.git"
  exit 1
fi

# Step 1: 同步 unstable
echo ">>> [1/4] 同步 $UPSTREAM_BRANCH 到最新上游..."
run git checkout "$UPSTREAM_BRANCH"
run git pull "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
run git push origin "$UPSTREAM_BRANCH"
echo

# Step 2: 生成本地工作分支
echo ">>> [2/4] 基于 $UPSTREAM_BRANCH 创建分支 $WORK_BRANCH..."
if git rev-parse --verify "$WORK_BRANCH" &>/dev/null; then
  echo "  [!] 分支 $WORK_BRANCH 已存在，删除重建..."
  run git branch -D "$WORK_BRANCH"
fi
run git branch "$WORK_BRANCH" "$UPSTREAM_BRANCH"
run git checkout "$WORK_BRANCH"
echo

# Step 3: 从 main 拉取补丁
echo ">>> [3/4] 从 $PATCHES_BRANCH 拉取补丁文件..."
run git checkout "$PATCHES_BRANCH" -- .patches/ scripts/
echo

# Step 4: 应用补丁并合并提交
echo ">>> [4/4] 应用补丁并合并提交..."
run bash .patches/apply-patches.sh
run git add -A
run git commit -m "apply local patches on top of $UPSTREAM_BRANCH @ $(date '+%Y%m%d')"
echo

echo "============================================"
echo "  同步完成"
echo "  当前分支: $WORK_BRANCH ($(git rev-parse --short HEAD))"
echo "  基于: $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
echo "  补丁: $PATCHES_BRANCH 分支"
echo "============================================"
