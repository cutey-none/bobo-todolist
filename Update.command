#!/bin/zsh
# Finder 中双击即可更新；路径始终相对于此文件，不依赖终端所在目录。
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
zsh "$ROOT_DIR/macos/upgrade.sh" "$@"
RESULT=$?
if [[ -t 0 ]]; then
    read "?按回车关闭此窗口…"
fi
exit "$RESULT"
