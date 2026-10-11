#!/bin/zsh
# 本机构建 release，生成可拖入 Applications 安装的压缩只读 DMG。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ $(uname -s) == Darwin ]] || { print -u2 'DMG 打包仅适用于 macOS。'; exit 1; }
[[ $# == 0 ]] || { print -u2 '用法：macos/package-dmg.sh'; exit 1; }
"$SCRIPT_DIR/build.sh" release
APP_DIR="$SCRIPT_DIR/build/QuadrantTodo.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")
ARCH=$(uname -m)
DMG_NAME="QuadrantTodo_${VERSION}_${ARCH}.dmg"
OUTPUT_DIR="$SCRIPT_DIR/build"
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.dmg-stage.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/image"
ditto "$APP_DIR" "$WORK_DIR/image/QuadrantTodo.app"
ln -s /Applications "$WORK_DIR/image/Applications"
codesign --verify --deep --strict "$WORK_DIR/image/QuadrantTodo.app"
hdiutil create -volname 'QuadrantTodo' -srcfolder "$WORK_DIR/image" \
    -format UDZO -fs HFS+ "$WORK_DIR/$DMG_NAME"
hdiutil verify "$WORK_DIR/$DMG_NAME"
# 只在镜像完整创建并验证后替换旧产物。
mv -f "$WORK_DIR/$DMG_NAME" "$OUTPUT_DIR/$DMG_NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
print -- "已生成：$OUTPUT_DIR/$DMG_NAME"
print -- "校验文件：$OUTPUT_DIR/$DMG_NAME.sha256"
