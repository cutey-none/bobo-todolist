#!/bin/zsh
# 将项目的 PNG 原图转换为包含 Retina 尺寸的 macOS 图标。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_SOURCE="$SCRIPT_DIR/Resources/AppIcon.png"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quadrant-icon.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$SCRIPT_DIR/Resources/AppIcon.icns"
print -- "已生成：$SCRIPT_DIR/Resources/AppIcon.icns"
