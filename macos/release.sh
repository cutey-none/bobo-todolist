#!/bin/zsh
# 一键发版：更新版本号、测试、打包 DMG、提交打 tag，并发布供应用内更新使用的 GitHub Release。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST="$SCRIPT_DIR/Resources/Info.plist"
fail() { print -u2 -- "$*"; exit 1; }

(( $# >= 1 && $# <= 2 )) || fail '用法：macos/release.sh <版本号，如 0.0.2> [Release 说明]'
VERSION="$1"
NOTES="${2:-}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "版本号须为 x.y.z：$VERSION"
TAG="v$VERSION"
command -v gh >/dev/null || fail '需要 GitHub CLI（gh）并已登录。'

cd "$ROOT_DIR"
[[ $(git branch --show-current) == main ]] || fail '请在 main 分支上发版。'
git diff --quiet && git diff --cached --quiet || fail '工作区有未提交的修改，请先处理。'
git fetch --quiet origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || fail 'main 与 origin/main 不一致，请先同步。'
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG 已存在。"

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
[[ "$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)" == "$VERSION" && "$CURRENT" != "$VERSION" ]] \
    || fail "新版本 $VERSION 必须高于当前版本 $CURRENT。"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
[[ "$BUILD" =~ '^[0-9]+$' ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"

(cd "$SCRIPT_DIR" && swift test) || { git checkout -- "$PLIST"; fail '测试失败，已撤销版本号修改。'; }
"$SCRIPT_DIR/package-dmg.sh" || { git checkout -- "$PLIST"; fail '打包失败，已撤销版本号修改。'; }

DMG="$SCRIPT_DIR/build/QuadrantTodo_${VERSION}_$(uname -m).dmg"
[[ -f "$DMG" && -f "$DMG.sha256" ]] || fail "未找到安装包：$DMG"

git add "$PLIST"
git commit -m "chore: release $TAG"
git tag -a "$TAG" -m "$TAG"
git push origin main "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "四象限待办 $TAG" \
    --notes "${NOTES:-四象限待办 $TAG}" --latest
print -- "已发布 $TAG，已安装的应用可在「检查更新…」中升级。"
