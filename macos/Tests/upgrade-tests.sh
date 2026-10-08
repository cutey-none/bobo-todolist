#!/bin/zsh
# 用临时 Git 仓库和模拟构建测升级流程；不运行或替换用户真实应用。
set -euo pipefail
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quadrant-upgrade-tests.XXXXXX")
print -- "测试文件保留在：$TASK_DIR"
mkdir -p "$TASK_DIR/tools" "$TASK_DIR/repo/macos" "$TASK_DIR/data/Attachments" "$TASK_DIR/install/QuadrantTodo.app/Contents/MacOS"
cp "$TEST_DIR/UpgradeFixtures/pgrep" "$TEST_DIR/UpgradeFixtures/defaults" "$TEST_DIR/UpgradeFixtures/codesign" "$TASK_DIR/tools/"
chmod +x "$TASK_DIR/tools/"*
export PATH="$TASK_DIR/tools:$PATH"
export QT_DATA_DIR="$TASK_DIR/data"
export QT_BACKUP_DIR="$TASK_DIR/backups"
export QT_TEST_SETTINGS="$TASK_DIR/settings.plist"
cp "$TEST_DIR/../Resources/Info.plist" "$QT_TEST_SETTINGS"
cp "$QT_TEST_SETTINGS" "$QT_DATA_DIR/Tasks.store"
cp "$QT_TEST_SETTINGS" "$QT_DATA_DIR/Tasks.store-wal"
cp "$QT_TEST_SETTINGS" "$QT_DATA_DIR/Attachments/image.png"
cp "$QT_TEST_SETTINGS" "$TASK_DIR/install/QuadrantTodo.app/Contents/MacOS/QuadrantTodo"
cp "$TEST_DIR/../upgrade.sh" "$TASK_DIR/repo/macos/upgrade.sh"
cp "$TEST_DIR/UpgradeFixtures/build.sh" "$TASK_DIR/repo/macos/build.sh"
cp "$TEST_DIR/../README.md" "$TASK_DIR/repo/macos/fixture-version"
cd "$TASK_DIR/repo"
git init -q -b main
git config user.name 'Upgrade Test'
git config user.email 'upgrade-test@example.invalid'
git add .
git commit -qm 'test: seed upgrade fixture'
TARGET="$TASK_DIR/install/QuadrantTodo.app"
check_data() {
    cmp "$QT_TEST_SETTINGS" "$QT_DATA_DIR/Tasks.store"
    cmp "$QT_TEST_SETTINGS" "$QT_DATA_DIR/Tasks.store-wal"
    cmp "$QT_TEST_SETTINGS" "$QT_DATA_DIR/Attachments/image.png"
}
run_upgrade() { zsh macos/upgrade.sh --app "$TARGET" --no-open "$@"; }
expect_failure() {
    if run_upgrade "$@"; then print -u2 '错误：预期拒绝升级'; exit 1; fi
    cmp "$QT_TEST_SETTINGS" "$TARGET/Contents/MacOS/QuadrantTodo"
    check_data
}
export QT_TEST_RUNNING=1
expect_failure --no-pull
export QT_TEST_RUNNING=0 QT_TEST_BUILD_FAIL=1
expect_failure --no-pull
export QT_TEST_BUILD_FAIL=0
cp "$QT_TEST_SETTINGS" macos/fixture-version
expect_failure --no-pull
git restore macos/fixture-version
# 模拟存在尚未推送提交，升级应拒绝，不重置本地代码。
git clone -q --bare . "$TASK_DIR/remote.git"
git remote add origin "$TASK_DIR/remote.git"
git fetch -q origin
git branch --set-upstream-to=origin/main main >/dev/null
cp "$QT_TEST_SETTINGS" extra-file
git add extra-file
git commit -qm 'test: local-only commit'
expect_failure
git push -q origin main
# 新远程提交：验证拉取、构建、替换以及完整备份。
git clone -q "$TASK_DIR/remote.git" "$TASK_DIR/author"
git -C "$TASK_DIR/author" config user.name 'Upgrade Test'
git -C "$TASK_DIR/author" config user.email 'upgrade-test@example.invalid'
cp "$TEST_DIR/../Resources/Info.plist" "$TASK_DIR/author/remote-file"
git -C "$TASK_DIR/author" add remote-file
git -C "$TASK_DIR/author" commit -qm 'test: remote update'
git -C "$TASK_DIR/author" push -q origin main
run_upgrade
[[ -f remote-file ]]
cmp macos/fixture-version "$TARGET/Contents/MacOS/QuadrantTodo"
check_data
SUCCESS_BACKUP=""
for candidate in "$QT_BACKUP_DIR"/upgrade-*(/); do
    if [[ -d "$candidate/Previous.app" ]]; then SUCCESS_BACKUP="$candidate"; fi
done
[[ -n "$SUCCESS_BACKUP" ]]
cmp "$QT_TEST_SETTINGS" "$SUCCESS_BACKUP/Data/Tasks.store"
cmp "$QT_TEST_SETTINGS" "$SUCCESS_BACKUP/Data/Tasks.store-wal"
cmp "$QT_TEST_SETTINGS" "$SUCCESS_BACKUP/Data/Attachments/image.png"
cmp "$QT_TEST_SETTINGS" "$SUCCESS_BACKUP/Settings.plist"
cmp "$QT_TEST_SETTINGS" "$SUCCESS_BACKUP/Previous.app/Contents/MacOS/QuadrantTodo"
print '通过：运行中拒绝、构建失败保留旧版、脏源码拒绝、本地提交拒绝、远程快进成功、数据库/附件/设置完整备份。'
