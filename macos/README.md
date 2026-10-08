# 四象限待办 · macOS 原生应用

贴边悬浮的四象限待办工具，SwiftUI + SwiftData 实现，无网络、无账号、数据只存本机。

## 环境准备

- 系统：macOS 14 Sonoma 或更新版本（使用 SwiftData，旧系统不能运行）。
- 推荐工具链：Xcode 15 或更新版本，包含 Swift 5.9+ 和 macOS 14+ SDK。安装后首次打开 Xcode，接受许可并完成组件安装；在 Xcode → Settings → Locations 中选择 Command Line Tools。
- 支持 Apple Silicon 与 Intel Mac。脚本默认编译当前电脑的架构；另一台电脑应从源码本机构建，不要依赖从不同架构电脑复制来的 `.app`。
- 不需要 Homebrew、Node.js、Python、CodeGraph、额外 Swift 包或 Apple Developer 付费账号。只安装 Command Line Tools 时，也须确保它提供满足上述版本要求的 Swift 与 macOS SDK。

打开终端检查：

```bash
xcode-select -p
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
```

Swift 应为 5.9 或更新版本，macOS SDK 应为 14.0 或更新版本。如果提示工具不存在，先安装 Xcode；如果已安装但选中了旧工具链，可执行（Xcode 位于默认安装路径时）：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

## 构建与运行

在新电脑上获取源码并构建：

```bash
git clone https://github.com/cutey-none/bobo-todolist.git
cd bobo-todolist
./macos/build.sh           # 编译 release 并生成 macos/build/QuadrantTodo.app
open macos/build/QuadrantTodo.app
```

如果已经位于仓库的 `macos/` 目录，也可以执行：

```bash
./build.sh                 # 编译 release 并生成 build/QuadrantTodo.app
open build/QuadrantTodo.app
```

成功时终端显示 `已生成：…/macos/build/QuadrantTodo.app`。脚本使用 Swift Package Manager 编译并组装 `.app`，无需创建 Xcode 工程；生成物和编译缓存不会提交到 Git。

### 首次使用

应用常驻菜单栏，**没有 Dock 图标，也不会默认弹出普通主窗口**。默认屏幕右侧有贴边条：悬停展开，或点击顶部菜单栏的待办图标、按 `⌥Space` 展开。菜单栏图标右键（或 Control-click）可打开设置与退出应用。

在任一象限末尾输入待办并按回车保存；点圆圈完成。单击标题编辑事项和 Markdown 描述，点「保存」写入；单击行空白或箭头查看描述。退出后重开，任务和描述应仍在。

全新数据目录首次启动时只创建 4 条示例：四个象限各一条，其中「整理桌面文件」已经完成（所以顶栏显示 3 个待办，Q4 显示「已完成 1」）。示例只在从未初始化的空库中创建一次。已有数据、升级后的数据以及用户主动清空后的空库都不会再次塞入示例，也不会为了凑成 4 条而删除或覆盖事项。

### 安装到「应用程序」

先通过菜单栏右键 →「退出四象限待办」退出已运行的实例。以下命令从**仓库根目录**执行；若已安装旧版，先在 Finder 中将 `/Applications/QuadrantTodo.app` 移到废纸篓，避免 `cp -R` 合并旧包。移除应用包不会删除本地待办数据。

```bash
cp -R macos/build/QuadrantTodo.app /Applications/
open /Applications/QuadrantTodo.app
```

若没有系统「应用程序」目录的写入权限，可在 Finder 中安装到个人的 `~/Applications/`。以后启动安装后的应用即可，无需每次编译；不要同时运行源码目录与安装目录中的两个实例。

### 安全更新且保留待办

先保存编辑内容并从菜单栏退出应用，再在仓库根目录双击 `Update.command`；也可以在终端执行：

```bash
./Update.command
```

更新入口会：

1. 拒绝在应用仍运行、源码有未提交修改、分支包含未推送提交或已经分叉时继续，绝不重置本地代码。
2. 在 `~/Library/Application Support/QuadrantTodoBackups/` 建立带时间的备份，包含整个数据目录（数据库、SQLite 辅助文件、图片附件）、设置；若已有旧应用，也一并保留。
3. 只接受当前分支的远程快进更新，在独立临时目录构建并验签；构建失败时旧应用不动。
4. 构建成功后才替换应用并重新打开。优先更新 `/Applications/QuadrantTodo.app`，其次是 `~/Applications/QuadrantTodo.app`，否则更新仓库里的 `macos/build/QuadrantTodo.app`。

它不会移动或改写 `~/Library/Application Support/QuadrantTodo/` 中的现有待办数据。应用启动时仍会执行兼容迁移，但迁移沿用仓库的本地持久化与失败保护规则。若要指定其他应用位置：

```bash
./Update.command --app "$HOME/Applications/QuadrantTodo.app"
```

有意只重建当前代码、不从 GitHub 拉取时使用 `./Update.command --no-pull`。如果 `/Applications` 没有写入权限，脚本不会索要管理员密码；可把应用安装到 `~/Applications/` 后用上面的 `--app` 路径更新。

### 常见问题

- `Permission denied`（脚本执行权限丢失）：从仓库根目录运行 `zsh macos/build.sh`。
- 找不到 Swift、SDK 或 SwiftData，或提示 tools version 不兼容：检查上面的工具链版本和 `xcode-select` 路径；更新 Xcode 后重新选择工具链。
- 切换 Xcode 后出现缓存 / 模块版本错误：从仓库根目录执行 `cd macos`、`swift package clean`、`./build.sh`，重新构建。
- 打开后看不到窗口：先检查菜单栏图标和屏幕贴边条；全局快捷键可能与其他软件冲突，可在菜单栏右键 →「设置…」换预设。
- macOS 阻止打开：脚本只有 ad-hoc 签名，没有 Developer ID 公证。从自己信任的源码本机重新构建；如仍被拦截，按系统提示在「系统设置 → 隐私与安全性」中确认打开。不要全局关闭 Gatekeeper。签名警告不代表已通过系统安全检查。
- 找不到新功能：确认已重新构建并替换安装版，而且没有旧实例仍在运行。
- 更新提示“源码有尚未提交的修改”或“本地有未推送提交”：先提交/推送自己的改动，或另建一个干净 clone；更新入口不会替你覆盖本地内容。

## 数据备份与换机

默认数据目录是 `~/Library/Application Support/QuadrantTodo/`，包含 `Tasks.store`、可能存在的 SQLite 辅助文件以及 `Attachments/` 图片目录。设置中的数据位置入口可在 Finder 中定位数据库。设置保存在本机 UserDefaults，仓库与 `.app` **不包含你的任务数据**，替换 `.app` 或更新源码不会删除待办，也不会自动同步到另一台电脑。

如需迁移任务：先在两台电脑退出应用，备份两边的数据目录，再将旧电脑的**整个 `QuadrantTodo/` 数据目录**复制到新电脑的同一路径（确认后替换，不能只复制数据库而遗漏图片）。新电脑使用同版本或更新版本的应用打开；窗口位置和快捷键等设置需重新设置。Markdown 中自行填写的绝对图片路径 / `file://` 路径还需另行迁移对应文件；应用插入的相对附件随 `Attachments/` 一起迁移。

## 开发与测试

以下命令从仓库根目录执行：

```bash
cd macos
swift test
./build.sh debug
open build/QuadrantTodo.app
```

也可用 `swift build && .build/debug/QuadrantTodo` 直接启动调试可执行文件。开发用环境变量建议直接传给可执行文件（不要依赖 `open` 给已有实例传递变量）：

```bash
QT_DATA_DIR="$(mktemp -d)" QT_START_EXPANDED=1 ./build/QuadrantTodo.app/Contents/MacOS/QuadrantTodo
```

`QT_DATA_DIR` 隔离数据库和附件，**不隔离 UserDefaults 设置**；首次示例数据也受本机设置影响。该命令的数据保存在临时目录，不会自动迁移到正式数据目录。

可用启动参数（开发用）：

- `QT_START_EXPANDED=1` 启动即展开面板
- `QT_KEEP_OPEN=1` 关闭「鼠标移出自动收起」
- `QT_DATA_DIR=/某个目录` 使用独立的数据目录（数据库与图片附件），不影响真实数据
- `QT_FAIL_SAVES=1` 模拟本地写入失败，用于验证失败时保留原状态与草稿
- `QT_UI_SCRIPT=脚本 QT_UI_DIR=目录`（仅 debug 构建）按脚本向面板投递真实点击 / 输入事件，用于无辅助功能权限时的界面验证，命令说明见 `DebugUIDriver.swift`

## 功能对照 PRD

| 需求 | 实现 |
| --- | --- |
| F1 贴边悬浮窗 | 无边框 `NSPanel`，`LSUIElement` 无 Dock 图标；支持上 / 下 / 左 / 右四边，以及自由浮动位置 |
| F2 展开 / 收起 | 悬停贴边条 120ms 展开；鼠标移出面板 1s 收回（展开描述或有撤销提示时 2.5s）；`⌥Space` 全局快捷键；菜单栏可展开 / 收起 / 钉住 |
| F3 四象限视图 | 一行顶栏「优先矩阵 · 日期 …… N 个待办 · 收起」（只计未完成）；主内容宽度 ≥ 600pt 时 2×2（默认窗口即是），否则 Q1→Q4 纵向单列（同一布局切换，草稿 / 焦点 / 展开状态不丢）；象限标题带颜色圆点；已完成按象限折叠为「已完成 N」 |
| F4 任务管理 | 圆圈是唯一完成入口，本地保存成功后才移入已完成区（失败时保持原状并提示），完成后 5 秒内可撤销并回到原位置；恢复未完成追加到末尾；删除在编辑浮层内，8 秒内可逐项撤销；从行空白或悬停出现的行首把手拖拽排序 / 跨象限，右键菜单提供「移至象限」「上移 / 下移」 |
| F5 快速添加 | 每个象限末尾常驻一行浅色「输入新待办…」（悬停 / 聚焦才出现底色），点击整行即可输入；回车保存成功后追加到该象限末尾、清空并保持焦点；空白或超过 200 字会提示且不创建；`Esc` 清空草稿；全局快捷键 / `⌘N` 聚焦最近使用的输入行并短暂高亮该象限 |
| F6 本地持久化 | SwiftData（SQLite）落在 `~/Library/Application Support/QuadrantTodo/Tasks.store` |
| F7 事项描述 | 描述以 **Markdown** 保存；单击**行空白或行尾箭头**原地展开渲染后的描述（同时只展开一项；有描述的事项常显箭头）；单击**标题**（悬停时浅底 + 小铅笔）打开编辑浮层：事项名称是页面级标题，与 Markdown 描述同在一个编辑外框（已有描述时先预览、单击正文进入编辑；工具栏可设正文 / 小标题 / 列表，可插入或粘贴图片）；点「保存」才写入，有未保存修改时 Esc / 点遮罩 / 关闭 / 取消统一询问保存、放弃或继续编辑 |

面板内快捷键：`⌘N` 聚焦输入行 · `↑ ↓` 选中任务 · `Space` 完成 · `⌘⌫` 删除 · `⌘Z` 撤销 · `Esc` 清空输入草稿 / 收起 · 编辑浮层内 `⌘S` 保存。

## 拖动与四边吸附

- 展开面板后可拖动窗口背景；收起态也可直接拖动贴边条，拖动开始时会先展开完整面板。
- 只有鼠标或窗口外缘真正进入屏幕边缘 `28pt` 范围并松手，才会吸附到对应的上 / 下 / 左 / 右边并立即收起。
- 没有进入边缘范围时只是普通移动：窗口停在松手位置、保持展开，不会自动寻找“最近边”，也不会因鼠标移出而自动收起。
- 自由浮动位置、吸附边缘及沿边位置都会保存；下次启动恢复。自由浮动时手动点「收起」会回到上一次贴边位置再收起。
- 设置页和菜单栏仍可直接指定四个贴边方向。

## 窗口尺寸与滚动

面板尺寸不随内容自适应，但可以**直接拖动面板边缘或四角调整**（鼠标移到边缘会出现调整光标，被拖的边跟随鼠标、对边不动；贴边停靠时贴屏幕的那一边不可拖；松手后尺寸与位置都会保存）。也可以在设置里调整：默认 `680 × 560pt`（打开即 2×2），可在 设置 →「窗口大小」里改（宽度 / 高度步进器，20pt 一档；预设「紧凑 420×320 / 默认 680×560 / 宽松 960×680」；「恢复默认」），改动即时生效并记在 UserDefaults。

- **纵向**：内容超过窗口高度时整体上下滚动，顶栏固定不动；不再横向滚动。
- **2×2 / 单列**：窗口宽度约 650pt 以上（主内容 ≥ 600pt）时四象限 2×2，否则纵向单列；象限较窄时自动使用紧凑间距。
- **悬停看全文**：长标题单行截断，悬停标题会弹出 tooltip，显示完整标题 + 描述摘要 + 所属象限。

设置窗口：菜单栏图标右键 →「设置…」，或面板聚焦时按 `⌘,`。

## 结构

```
macos/
  Sources/QuadrantTodo/
    App.swift                  应用入口、菜单栏与依赖装配
    Core/                      模型、仓储、设置、窗口控制器、全局快捷键
      MarkdownDocument.swift   事项描述 Markdown 的块解析
      TaskDescription.swift    旧版 JSON 描述块到 Markdown 的迁移
      AttachmentStore.swift    描述图片附件的保存与读取
      ProgressEntry.swift      旧进度数据模型，仅用于启动迁移与兼容
      ImageAttachment.swift    图片压缩与规范化
    Views/                     贴边条、面板、象限卡片、任务行、编辑浮层、设置
  Resources/Info.plist         LSUIElement / 版本信息
  build.sh                     构建并组装 .app
  upgrade.sh                   备份数据、拉取、隔离构建并安全替换应用
Update.command                 可双击运行的更新入口
```

## 已知限制（v0.1）

- 每个事项描述最多 6 张图片，最长边压缩到 1600px，保存在数据目录的 `Attachments/` 下，Markdown 中以 `![图片](attachments/文件名)` 引用；描述与图片只保存在本机，不支持云同步。
- Markdown 支持小标题（`#`–`######`）、正文、`-`/`*` 列表、有序列表、引用、代码块、整行图片，以及加粗 / 斜体 / 行内代码 / 链接等行内样式；不支持表格。
- 旧版本已有的备注、进度与结构化描述会在启动时迁移为 Markdown（图片转存为附件文件），原时间线不再显示。
- 删除事项或从描述中移除图片引用后，附件文件不会立即清理。

- 全局快捷键提供 3 个预设（⌥Space / ⌃⌥Space / ⌥T），不做任意键位录制。
- 吸附边缘、沿边位置和自由浮动位置会在下次启动恢复；多显示器以松手时鼠标所在屏幕为准，不保存显示器身份。
- 拖拽使用系统拖放，落点按目标卡片 / 目标行计算，不显示插入位置预览线。

## 验证

功能点逐项验证记录（含截图）见 [`../docs/verify/README.md`](../docs/verify/README.md)。

2026-10-07 构建指南核验：在 Apple Silicon、macOS 26.5.2、Swift 6.3.3 环境，从 Git 已跟踪源码导出到独立临时目录（不含原工作目录的 `.build/` 缓存和未跟踪文件），执行 `./macos/build.sh` 成功，`swift test` 的 24 项测试全部通过；工作目录应用也已重建，`codesign --verify --deep --strict` 和 `plutil -lint` 检查通过。存在已有的 `withAnimation` 未使用返回值编译警告，不影响构建。尚未在 Intel Mac 或最低支持版本的系统 / 工具链上实测；上面的最低要求来自包配置和应用声明，不是完整兼容性测试结果。
