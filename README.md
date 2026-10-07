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

构建成功会显示 `已生成：…/macos/build/QuadrantTodo.app`。不需要 Homebrew、Node.js、Python、CodeGraph、第三方包或 Apple Developer 付费账号；构建脚本会进行本机 ad-hoc 签名，不是公证发行包。

完整的安装、更新、常见问题、数据备份与开发说明见 [macos/README.md](macos/README.md)。交互规格见 [产品文档](docs/prd/quadrant-todo-ui-prd.md)，运行验证记录见 [验证文档](docs/verify/README.md)。
