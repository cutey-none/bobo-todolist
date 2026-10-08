# 四象限待办

macOS 原生贴边待办工具，使用 SwiftUI + SwiftData，任务与 Markdown 描述图片保存在本机，无需账号。

## 在另一台 Mac 上构建并使用

需要 **macOS 14 Sonoma 或更新版本**，以及 **Xcode 15 或更新版本**（Swift 5.9+ 和 macOS 14+ SDK）。支持 Apple Silicon 和 Intel Mac；在目标电脑上构建会生成适合该电脑架构的应用，不要把单架构构建产物当作通用包。

1. 安装并首次打开 Xcode，完成许可确认和组件安装。在 Xcode → Settings → Locations 中选择 Command Line Tools。环境检查与选错工具链时的处理见 [macOS 构建指南](macos/README.md#环境准备)。
2. 在终端执行：

   ```bash
   git clone https://github.com/cutey-none/bobo-todolist.git
   cd bobo-todolist
   ./macos/build.sh
   open macos/build/QuadrantTodo.app
   ```

3. 应用没有 Dock 图标：点击顶部菜单栏的待办图标，或按 `⌥Space` 展开；默认屏幕右侧也有贴边条，悬停即可展开。在象限末尾输入待办，按回车保存。

全新数据首次启动只创建 4 条示例（每个象限一条，其中一条已完成）。这一步只发生一次；已有数据升级时不会添加、删除或覆盖任何待办。

以后更新时，先保存并退出应用，然后在仓库根目录双击 `Update.command`，或执行：

```bash
./Update.command
```

更新入口会备份数据库、图片附件、设置及旧应用，拉取 GitHub 更新并构建，成功后才替换应用。详细说明见 [macOS 构建指南](macos/README.md#安全更新且保留待办)。

### 另一台电脑已有事项，怎样保留并升级？

在**那台电脑**保存编辑内容并退出应用，然后进入它的源码仓库运行 `./Update.command`。事项和图片保存在该电脑用户目录的 `~/Library/Application Support/QuadrantTodo/`，与源码和 `.app` 分开；更新会先备份，再用最新代码本机构建并替换应用，继续读取原有数据。无需复制或替换数据目录，也不会为现有事项重新填入示例。

如果旧源码里还没有 `Update.command`，先在该电脑的干净仓库中运行 `git pull --ff-only`，再执行 `./Update.command`；只拉取源码还不会更新已经运行的应用。若源码有本地修改或分支分叉，先处理这些改动，脚本不会强制覆盖。

**换机迁移与软件升级是两件事**：新电脑不会从 GitHub 自动获得旧电脑的事项。需要迁移时，退出两边应用并备份后，复制整个数据目录（包含数据库辅助文件和图片附件），见 [数据备份与换机](macos/README.md#数据备份与换机)。若新电脑已有自己的事项，不要直接用旧电脑的数据目录覆盖；当前不支持两份事项数据库自动合并。

构建成功会显示 `已生成：…/macos/build/QuadrantTodo.app`。不需要 Homebrew、Node.js、Python、CodeGraph、第三方包或 Apple Developer 付费账号；构建脚本会进行本机 ad-hoc 签名，不是公证发行包。

完整的安装、更新、常见问题、数据备份与开发说明见 [macos/README.md](macos/README.md)。交互规格见 [产品文档](docs/prd/quadrant-todo-ui-prd.md)，运行验证记录见 [验证文档](docs/verify/README.md)。
