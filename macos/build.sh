#!/bin/zsh
# 构建 macOS 原生应用：编译 release 可执行文件并组装 .app 包。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIGURATION="${1:-release}"
[[ "$CONFIGURATION" == release || "$CONFIGURATION" == debug ]] || { print -u2 '用法：macos/build.sh [release|debug]'; exit 1; }
swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$SCRIPT_DIR/build/QuadrantTodo.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/QuadrantTodo" "$APP_DIR/Contents/MacOS/QuadrantTodo"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# 资源全部就位后签名；签名失败不能继续交付损坏的应用包。
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "已生成：$APP_DIR"
