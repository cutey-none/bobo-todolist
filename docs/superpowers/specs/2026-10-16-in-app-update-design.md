# 应用内更新设计

日期：2026-10-16
状态：待审核

## 1. 目标与约束

**目标**：用户在 app 内手动检查 GitHub Releases 上的最新版本，一键下载、替换 `.app` 并重启，全程不影响本地待办数据。

**用户已确认的决策**

- 只在用户手动点击「检查更新」时联网；不做启动自动检查、不做后台自动安装。
- 发现新版本后「升级」一键完成：下载 → 校验 → 备份 → 退出 → 替换 → 重新打开。
- 入口：设置页新增「关于与更新」区；菜单栏右键菜单新增「检查更新…」。
- 自研更新器，不引入 Sparkle 或任何第三方依赖。

**既有事实（来自代码）**

- 用户数据位于 `~/Library/Application Support/QuadrantTodo/`（`Tasks.store`、SQLite 辅助文件、`Attachments/`），或 `QT_DATA_DIR` 指定目录；设置位于 UserDefaults 域 `com.cutey.quadranttodo`。`.app` 内不含用户数据。
- 发布产物由 `macos/package-dmg.sh` 生成：`QuadrantTodo_<版本>_<arch>.dmg` 与同名 `.sha256`，以 GitHub Release（tag `v<版本>`）上传。当前只有 arm64。
- app 为 ad-hoc 签名，未公证；`LSUIElement` 菜单栏工具；非沙盒。
- `macos/upgrade.sh` 已有「备份 → 暂存 → 替换 → 失败还原」的源码升级流程，本设计沿用其备份布局。

**成功标准**

1. 0.0.1 安装版通过 app 内按钮升级到更高版本后自动重启，提示升级成功。
2. 升级前后数据目录内容逐文件哈希一致；设置保持不变。
3. 任一步骤失败时旧 app 仍可用、数据不变，并显示可理解的原因。
4. 不需要管理员密码、Xcode 或终端操作。

**非目标**：自动检查、增量更新、Universal 包、Developer ID 签名 / 公证、回滚 UI（手动回滚靠备份中的 `Previous.app`）。

## 2. 整体流程

1. **检查**：请求 `https://api.github.com/repos/cutey-none/bobo-todolist/releases/latest`（15 秒超时）。tag 去掉前缀 `v` 后与 `CFBundleShortVersionString` 按数字逐段比较。按本机架构（`arm64` / `x86_64`）选择资源 `QuadrantTodo_<版本>_<arch>.dmg` 及 `<同名>.sha256`。
   - 远端版本不高于当前 → 「已是最新版本」。
   - 远端更高但缺少本机架构 DMG 或 `.sha256` → 「新版本 x.y.z 暂无适用于本机（Intel/Apple 芯片）的安装包」。
   - 否则 → 显示版本号与 Release 说明，提供「升级」按钮。
2. **预检**（任何一项不通过即停止，不做任何改动）：
   - 编辑浮层打开中（`AppState.editing != nil`）→ 请先保存或关闭正在编辑的事项。
   - 任一象限输入行有非空草稿 → 请先提交或清空输入框中的草稿。
   - app 路径位于只读卷（如从 DMG 直接运行）或包含 `/AppTranslocation/` → 请先把应用拖到「应用程序」或 `~/Applications` 再升级。
   - `.app` 所在目录不可写 → 说明没有写入权限，不会索要管理员密码，可安装到 `~/Applications`。
3. **下载与校验**（不触碰现有 app 和数据）：
   - 下载 DMG 与 `.sha256` 到 `~/Library/Caches/QuadrantTodo/Updates/`，显示进度，可取消。
   - 计算 SHA-256，与 `.sha256` 第一字段比对，不一致即失败。
   - `hdiutil attach -nobrowse -readonly -noautoopen -mountrandom <临时目录>` 挂载。
   - 将镜像内 `QuadrantTodo.app` 用 `ditto` 复制到目标 app 同目录下的隐藏暂存目录 `.quadrant-update.XXXXXX/`（同卷，保证后续 `mv` 原子）。
   - `codesign --verify --deep --strict` 验签；读取暂存 app 的 Info.plist，要求 `CFBundleIdentifier == com.cutey.quadranttodo` 且 `CFBundleShortVersionString` 等于 Release 版本。
   - `hdiutil detach`（无论成功失败都执行）。
4. **备份**：在 `~/Library/Application Support/QuadrantTodoBackups/update-<yyyyMMdd-HHmmss>/` 下：
   - 数据目录取 `PersistenceController.storeURL()` 的父目录（自动遵循 `QT_DATA_DIR`），若存在则 `ditto` 到 `Data/`；
   - `defaults export com.cutey.quadranttodo Settings.plist`（域存在时）。
   - 备份失败即中止升级。
5. **替换与重启**：
   - 将助手脚本写入临时目录，以 `/bin/zsh helper.sh <pid> <暂存 app> <目标 app> <备份目录> <结果文件>` 启动（独立进程，不随 app 退出）。
   - app 调用 `NSApp.terminate(nil)`，经由现有 `applicationWillTerminate` 完成待删除事项。
   - 助手：等待 pid 退出（最多 30 秒）→ `mv 目标 备份/Previous.app` → `mv 暂存 目标` → 失败则把 `Previous.app` 移回 → 清理暂存目录 → 写结果文件 → `open 目标`。
6. **启动后反馈**：app 启动时读取结果文件 `~/Library/Caches/QuadrantTodo/Updates/last-result.json`，通过 `AppState` 的 notice 显示「已升级到 x.y.z」或「升级失败，已保留旧版本。备份位于 …」，随后删除结果文件。

**数据保证**：流程只移动 `.app`，从不写入数据目录与 UserDefaults；备份是额外保险。新版启动照常执行现有兼容迁移。

**Gatekeeper**：非沙盒 app 用 `URLSession` 下载的文件不带 `com.apple.quarantine`，替换后的新版直接打开。运行验证中需实测确认；若实测带有该属性，安装器对暂存 app 执行 `xattr -dr com.apple.quarantine`（仅限已通过校验和与签名验证的暂存 app）。

## 3. 模块划分

新代码位于 `macos/Sources/QuadrantTodo/Core/Update/`。纯逻辑与副作用分离。

| 模块 | 职责 | 依赖 |
| --- | --- | --- |
| `AppVersion` | 解析 `0.0.1` / `v0.1.0`，数字逐段比较，缺段按 0；无法解析返回 nil | 无 |
| `ReleaseInfo` | 解码 GitHub `releases/latest` JSON（`tag_name`、`body`、`assets[].name`、`assets[].browser_download_url`）；按版本与架构选出 DMG 和 `.sha256` 资源 | 无 |
| `UpdatePreflight` | 输入（是否在编辑、草稿是否为空、app 路径、卷是否只读、目录是否可写），输出 `.ok` 或具体拒绝原因；不读全局状态 | 无 |
| `UpdateInstaller` | 下载、SHA-256、挂载、暂存、验签、核对 Info.plist、备份、启动助手；每步为独立 `async throws` 函数，外部命令经可注入的 `CommandRunner` 执行 | `URLSession`、`Process`、`FileManager`、`CryptoKit` |
| `UpdateHelperScript` | 助手 zsh 脚本内容（Swift 字符串常量）及落盘 | 无 |
| `UpdateController` | `@MainActor ObservableObject` 状态机，串联上述模块，供设置页和菜单使用 | 上述模块、`AppState` |

`UpdateController.Phase`：`idle`、`checking`、`upToDate`、`available(version, notes)`、`unavailableForArch(version)`、`downloading(progress)`、`preparing`、`relaunching`、`failed(message)`。

**现有文件改动**

- `Views/SettingsView.swift`：新增「关于与更新」区：当前版本；按 phase 显示「检查更新」/「升级到 x.y.z」/「取消」按钮、进度条、状态文字；Release 说明默认截断，可展开。
- `Core/StatusItemController.swift`：右键菜单在「设置…」之前加入「检查更新…」，打开设置窗口并立即开始检查。
- `App.swift`：创建 `UpdateController` 并注入设置页与菜单；启动时读取结果文件并显示 notice。
- 开发用环境变量 `QT_UPDATE_FEED_URL`：覆盖 `releases/latest` 地址（可为 `file://` 或本地 http），用于验证。

## 4. 错误处理

- 进入替换前的任何失败都不改动现有 app 和数据；清理下载文件与暂存目录，设置页显示原因。错误类型：网络失败 / 超时、响应无法解析、无适用架构、校验和不一致、挂载失败、签名无效、版本或 bundle id 不匹配、目录不可写、备份失败、用户取消。
- 备份失败即中止，不在无备份情况下替换。
- 助手脚本：
  - 等待 pid 超时 → 不替换，写失败结果，重新打开旧版；
  - 移走旧 app 后放置新 app 失败 → 将 `Previous.app` 移回原位，写失败结果，打开旧版；
  - 成功 → 写成功结果，打开新版；`Previous.app` 保留在备份目录供手动回滚。
- 只在用户点击时请求网络，不做自动重试。GitHub 未认证 API 每小时 60 次限制对手动检查足够；遇到 403 / 429 显示「请求过于频繁，请稍后再试」。

## 5. 测试

**单元测试（`swift test`）**

- `AppVersion`：相等、更大、更小、缺段、`v` 前缀、非数字段。
- `ReleaseInfo`：正常解析；仅有 arm64；缺 `.sha256`；tag 无法解析；资源名大小写/版本不一致。
- `UpdatePreflight`：每种拒绝原因及 `.ok`。
- SHA-256 文件解析（`<hash>  <name>` 格式）与比对。

**助手脚本测试（XCTest + 临时目录）**

用两个假 `.app` 目录和一个短生命周期进程（如 `sleep`）验证：替换成功、等待超时放弃、放置失败后还原。

## 6. 运行验证（截图存 `docs/verify/`）

1. 本地将 Info.plist 改为 `0.0.2` 打包 DMG 与 `.sha256`，编写假 `releases/latest` JSON 指向这些文件。
2. 将 0.0.1 构建安装到 `~/Applications`，用独立 `QT_DATA_DIR` 准备若干事项与图片附件，记录数据目录逐文件哈希。
3. 以 `QT_UPDATE_FEED_URL` 启动，依次「检查更新」→「升级」。
4. 确认：自动重启并提示「已升级到 0.0.2」；数据目录哈希一致；备份目录含 `Data/` 与 `Previous.app`；新 app 无 quarantine 属性。
5. 截图：已是最新、发现新版本、下载中、失败（篡改 `.sha256` 触发）、升级成功提示。

## 7. 文档

- `macos/README.md`：「无网络」改为「仅在手动检查更新时访问 GitHub」；新增「在应用内更新」；写明发版约定（tag `vX.Y.Z` 与 Info.plist 版本一致，上传 DMG 与 `.sha256`，资源名不可改）。
- `docs/prd/quadrant-todo-ui-prd.md`：补充设置页「关于与更新」区与菜单项的交互。

## 8. 提交拆分

1. `feat`: 版本比较与 Release 解析 + 测试
2. `feat`: 升级预检 + 测试
3. `feat`: 下载、校验、暂存、备份与助手脚本 + 测试
4. `feat`: 更新控制器与设置页「关于与更新」区
5. `feat`: 菜单入口与升级结果提示
6. `docs`: README 与 PRD
7. `docs`: 运行验证截图与说明
