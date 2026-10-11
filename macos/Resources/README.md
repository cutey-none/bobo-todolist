# 应用图标

`AppIcon.png` 是四象限待办的 Logo 原图；`AppIcon.icns` 包含 Finder 使用的多尺寸与 Retina 图标。四块红、黄、绿、蓝圆角矩阵对应四象限，白色勾代表完成；象牙白玻璃底板呼应应用的 macOS 外观。

2026-10-11 使用内置 imagegen 工具生成，无外部参考图。最终提示词：

> Use case: logo-brand. Create one polished macOS application icon for QuadrantTodo, a four-quadrant priority todo app. Single square 1024x1024 icon, transparent outside a softly rounded square tile with generous consistent margin. Modern macOS minimal dimensional glass appearance, softly luminous ivory tile. Center a bold 2 by 2 matrix of four rounded colored squares: coral upper left, golden amber upper right, mint green lower left, soft blue lower right. A crisp white checkmark inside the coral square is the sole completion symbol. The four squares remain distinct, balanced, recognisable at small Finder icon sizes. Front view, subtle restrained shadows, no perspective, no text, no letters, no watermark, no extra objects. Deliver the icon itself, not an icon presentation board.

更换 PNG 后从仓库根目录执行 `./macos/generate-icon.sh`，再运行 `./macos/build.sh` 或 `./macos/package-dmg.sh`。转换只依赖 macOS 的 `sips` 与 `iconutil`，普通构建直接使用已提交的 ICNS，不需要图片生成服务。
