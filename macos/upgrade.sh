#!/bin/zsh
# 安全源码升级：保留数据、备份附件和设置，成功构建后才替换应用。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME=QuadrantTodo.app
APP_DOMAIN=com.cutey.quadranttodo
TARGET=""
PULL=1
OPEN_APP=1
fail() { print -u2 -- "$*"; exit 1; }
while (( $# )); do
    case "$1" in
        --app) (( $# >= 2 )) || fail '--app 后需要应用路径'; TARGET="$2"; shift 2 ;;
        --no-pull) PULL=0; shift ;;
        --no-open) OPEN_APP=0; shift ;;
        --help) print '用法：zsh macos/upgrade.sh [--app /路径/QuadrantTodo.app] [--no-pull] [--no-open]'; exit 0 ;;
        *) fail "未知参数：$1" ;;
    esac
done
[[ $(uname -s) == Darwin ]] || fail '此升级入口仅适用于 macOS。'
cd "$ROOT_DIR"
[[ -d .git || -f .git ]] || fail '请在 git clone 获得的源码目录中更新。'
git diff --quiet && git diff --cached --quiet || fail '源码有尚未提交的修改。请先保存或提交，不会自动覆盖或暂存。'
if pgrep -x QuadrantTodo >/dev/null; then
    fail '请先保存编辑中的内容，并从菜单栏退出四象限待办，再重新运行更新。'
fi
if [[ -z "$TARGET" ]]; then
    if [[ -d /Applications/$APP_NAME ]]; then
        TARGET="/Applications/$APP_NAME"
    elif [[ -d "$HOME/Applications/$APP_NAME" ]]; then
        TARGET="$HOME/Applications/$APP_NAME"
    else
        TARGET="$SCRIPT_DIR/build/$APP_NAME"
    fi
fi
[[ "$TARGET" == /* && "${TARGET:t}" == "$APP_NAME" && ! -L "$TARGET" ]] || fail '目标必须是非符号链接的绝对路径 QuadrantTodo.app。'
mkdir -p "${TARGET:h}"
[[ -w "${TARGET:h}" ]] || fail "没有写入权限：${TARGET:h}（不会使用 sudo）"
DATA_DIR="${QT_DATA_DIR:-$HOME/Library/Application Support/QuadrantTodo}"
BACKUP_ROOT="${QT_BACKUP_DIR:-$HOME/Library/Application Support/QuadrantTodoBackups}"
[[ "$DATA_DIR" == /* && "$BACKUP_ROOT" == /* ]] || fail '数据和备份目录必须是绝对路径。'
mkdir -p "$BACKUP_ROOT"
BACKUP_ROOT="$(cd "$BACKUP_ROOT" && pwd -P)"
if [[ -d "$DATA_DIR" ]]; then
    DATA_DIR="$(cd "$DATA_DIR" && pwd -P)"
    [[ "$BACKUP_ROOT" != "$DATA_DIR" && "$BACKUP_ROOT" != "$DATA_DIR/"* ]] || fail '备份目录不能位于待办数据目录内部。'
fi
BACKUP_DIR=$(mktemp -d "$BACKUP_ROOT/upgrade-$(date +%Y%m%d-%H%M%S).XXXXXX")
print -- "备份位置：$BACKUP_DIR"
if [[ -d "$DATA_DIR" ]]; then
    ditto "$DATA_DIR" "$BACKUP_DIR/Data"
fi
if defaults read "$APP_DOMAIN" >/dev/null 2>&1; then
    defaults export "$APP_DOMAIN" "$BACKUP_DIR/Settings.plist" >/dev/null
fi
if (( PULL )); then
    UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}') || fail '当前分支没有上游，请先配置跟踪分支。'
    BRANCH=$(git symbolic-ref --quiet --short HEAD) || fail '当前处于 detached HEAD，请切回跟踪分支。'
    REMOTE=$(git config "branch.$BRANCH.remote")
    [[ "$REMOTE" != '.' && -n "$REMOTE" ]] || fail '当前分支需要跟踪远程仓库。'
    git fetch "$REMOTE"
    git merge-base --is-ancestor HEAD "$UPSTREAM" || fail '本地有未推送提交或分支已分叉；请先处理，不会重置本地代码。'
    git merge --ff-only "$UPSTREAM"
fi
# 隔离构建：不覆盖现有应用，也不把编译生成物写入源码树。
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quadrant-upgrade.XXXXXX")
trap 'print -- "构建工作目录：$WORK_DIR"' EXIT
git archive HEAD | tar -x -C "$WORK_DIR"
zsh "$WORK_DIR/macos/build.sh"
NEW_APP="$WORK_DIR/macos/build/$APP_NAME"
codesign --verify --deep --strict "$NEW_APP"
# 构建可能耗时很久，再检查一次，避免用户期间启动旧版。
pgrep -x QuadrantTodo >/dev/null && fail '构建期间应用被启动。请退出后重新更新；旧版尚未替换。'
STAGED_DIR=$(mktemp -d "${TARGET:h}/.quadrant-upgrade.XXXXXX")
ditto "$NEW_APP" "$STAGED_DIR/$APP_NAME"
if [[ -e "$TARGET" ]]; then
    mv "$TARGET" "$BACKUP_DIR/Previous.app"
fi
if ! mv "$STAGED_DIR/$APP_NAME" "$TARGET"; then
    if [[ -d "$BACKUP_DIR/Previous.app" ]]; then mv "$BACKUP_DIR/Previous.app" "$TARGET"; fi
    fail '替换失败，已尝试还原旧应用；数据备份仍保留。'
fi
rmdir "$STAGED_DIR"
print -- "更新完成：$TARGET"
print '待办数据库、图片附件和设置未被替换。备份及旧应用已保留。'
if (( OPEN_APP )); then open "$TARGET"; fi
