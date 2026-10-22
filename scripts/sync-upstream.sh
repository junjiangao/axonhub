#!/usr/bin/env bash
#
# sync-upstream.sh — 同步上游 unstable，生成本地工作分支并应用补丁
#
# 用法:
#   ./scripts/sync-upstream.sh                    # 生成 work-YYYYMMDD
#   ./scripts/sync-upstream.sh work/my-feature    # 指定工作分支名
#   ./scripts/sync-upstream.sh --dry              # 试运行
#   ./scripts/sync-upstream.sh --no-color         # 关闭颜色
#
set -euo pipefail

UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="unstable"
PATCHES_BRANCH="main"
DRY_RUN=false
WORK_BRANCH=""
COLOR_DISABLED=false

# 默认启用颜色；--no-color 和 FORCE_COLOR=0 可显式关闭。
color_enabled() {
  if [ "$COLOR_DISABLED" = true ] || [ "${FORCE_COLOR:-}" = "0" ]; then
    return 1
  fi
  return 0
}

highlight_stream() {
  local enabled=false line lower color reset=$'\033[0m'
  if color_enabled; then enabled=true; fi

  while IFS= read -r line || [ -n "$line" ]; do
    lower="${line,,}"
    if [[ "$lower" == *error* || "$lower" == *exception* || "$lower" == *fatal:* || "$lower" == *failed* || "$lower" == *failure* || "$line" == *"异常"* || "$line" == *"错误"* || "$line" == *"失败"* ]]; then
      if [ "$enabled" = true ]; then
        color=$'\033[31;1m'
        printf '%s%s%s\n' "$color" "$line" "$reset"
      else
        printf '%s\n' "$line"
      fi
    elif [[ "$lower" == *warn* || "$line" == *"警告"* || "$line" == *"[!]"* ]]; then
      if [ "$enabled" = true ]; then
        color=$'\033[33;1m'
        printf '%s%s%s\n' "$color" "$line" "$reset"
      else
        printf '%s\n' "$line"
      fi
    else
      printf '%s\n' "$line"
    fi
  done
}

print_warning() {
  if color_enabled; then
    printf '\033[33;1m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

print_error() {
  if color_enabled; then
    printf '\033[31;1m%s\033[0m\n' "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

print_info() {
  if color_enabled; then
    printf '\033[36;1m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

print_run() {
  if color_enabled; then
    printf '\033[34;1m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

print_success() {
  if color_enabled; then
    printf '\033[32;1m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

for arg in "$@"; do
  case "$arg" in
    --dry) DRY_RUN=true ;;
    --no-color) COLOR_DISABLED=true ;;
    -*)
      print_warning "[!] 未知选项: $arg"
      echo "用法: $0 [分支名] [--dry] [--no-color]"
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
    print_info "  [DRY] $*"
  else
    print_run "  [RUN] $*"
    local stream_dir stdout_pid stderr_pid status
    stream_dir="$(mktemp -d)"
    mkfifo "$stream_dir/stdout" "$stream_dir/stderr"
    highlight_stream <"$stream_dir/stdout" &
    stdout_pid=$!
    highlight_stream <"$stream_dir/stderr" >&2 &
    stderr_pid=$!
    if "$@" >"$stream_dir/stdout" 2>"$stream_dir/stderr"; then
      status=0
    else
      status=$?
    fi
    wait "$stdout_pid" || true
    wait "$stderr_pid" || true
    rm -f "$stream_dir/stdout" "$stream_dir/stderr"
    rmdir "$stream_dir" || true
    if [ "$status" -ne 0 ]; then
      print_error "错误: 命令执行失败，退出码 $status: $*"
    fi
    return "$status"
  fi
}

print_info "============================================"
print_info "  AxonHub 同步脚本"
print_info "  上游: $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
print_info "  补丁: $PATCHES_BRANCH 分支"
print_info "  工  作分支: $WORK_BRANCH"
print_info "  日期: $(date '+%Y-%m-%d %H:%M:%S')"
print_info "============================================"
echo

if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
  print_warning "[!] 未找到 upstream remote，请先添加:"
  echo "    git remote add upstream git@github.com:looplj/axonhub.git"
  exit 1
fi

# Step 1: 同步 unstable
print_info ">>> [1/4] 同步 $UPSTREAM_BRANCH 到最新上游..."
# 本地无该分支时显式指定远端：origin 与 upstream 上的同名分支会让 git checkout 的短名解析报
# "matched multiple remote tracking branches"。优先跟踪 origin，保持与 origin 发布流程一致。
if git rev-parse --verify --quiet "refs/heads/$UPSTREAM_BRANCH" >/dev/null; then
  run git checkout "$UPSTREAM_BRANCH"
elif git rev-parse --verify --quiet "refs/remotes/origin/$UPSTREAM_BRANCH" >/dev/null; then
  run git checkout -b "$UPSTREAM_BRANCH" --track "origin/$UPSTREAM_BRANCH"
else
  run git checkout -b "$UPSTREAM_BRANCH" --track "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
fi
run git pull "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
run git push origin "$UPSTREAM_BRANCH"
echo

# Step 2: 生成本地工作分支
print_info ">>> [2/4] 基于 $UPSTREAM_BRANCH 创建分支 $WORK_BRANCH..."
if git rev-parse --verify "$WORK_BRANCH" &>/dev/null; then
  print_warning "  [!] 分支 $WORK_BRANCH 已存在，删除重建..."
  run git branch -D "$WORK_BRANCH"
fi
run git branch "$WORK_BRANCH" "$UPSTREAM_BRANCH"
run git checkout "$WORK_BRANCH"
echo

# Step 3: 从 main 拉取补丁
print_info ">>> [3/4] 从 $PATCHES_BRANCH 拉取补丁文件..."
run git checkout "$PATCHES_BRANCH" -- .patches/ scripts/
echo

# Step 4: 应用补丁并合并提交
print_info ">>> [4/4] 应用补丁并合并提交..."
run bash .patches/apply-patches.sh
run git add -A
run git commit -m "apply local patches on top of $UPSTREAM_BRANCH @ $(date '+%Y%m%d')"
echo

print_success "============================================"
print_success "  同步完成"
print_success "  当前分支: $WORK_BRANCH ($(git rev-parse --short HEAD))"
print_success "  基于: $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
print_success "  补丁: $PATCHES_BRANCH 分支"
print_success "============================================"
