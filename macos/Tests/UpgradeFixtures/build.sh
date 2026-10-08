#!/bin/zsh
set -eu
[[ "${QT_TEST_BUILD_FAIL:-0}" != 1 ]] || exit 42
cd "$(dirname "$0")"
mkdir -p build/QuadrantTodo.app/Contents/MacOS
cp fixture-version build/QuadrantTodo.app/Contents/MacOS/QuadrantTodo
