#!/bin/zsh
# 构建 macOS 原生应用：编译 release 可执行文件并组装 .app 包。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$SCRIPT_DIR/build/QuadrantTodo.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/QuadrantTodo" "$APP_DIR/Contents/MacOS/QuadrantTodo"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || echo "警告：ad-hoc 签名失败，应用仍可本地运行"

echo "已生成：$APP_DIR"
