import SwiftUI

enum Theme {
    static let red = Color(hex: 0xE5484D)
    static let blue = Color(hex: 0x3B82F6)
    static let orange = Color(hex: 0xF59E0B)
    static let gray = Color(hex: 0x6B7280)

    static let accent = Color(hex: 0x2F6FEB)
    static let secondaryText = Color.primary.opacity(0.55)
    static let hairline = Color.primary.opacity(0.08)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 面板尺寸与动效常量（PRD 12.5）。
enum Metrics {
    static let railWidth: CGFloat = 38
    static let railCorner: CGFloat = 12
    static let railHeight: CGFloat = 296
    static let screenMargin: CGFloat = 10
    /// 窗口边缘进入此距离后触发磁吸。
    static let edgeSnapThreshold: CGFloat = 28

    // 窗口尺寸：默认值取自 PRD 12.5（560 × 470pt），可在设置里修改。
    // 面板固定尺寸，不随内容自适应；超出部分靠滚动查看。
    static let defaultPanelWidth: CGFloat = 560
    static let defaultPanelHeight: CGFloat = 470
    static let minPanelWidth: CGFloat = 420
    static let minPanelHeight: CGFloat = 320
    static let maxPanelWidth: CGFloat = 1200
    static let maxPanelHeight: CGFloat = 960
    static let panelSizeStep: CGFloat = 20

    /// 四象限内容的最小布局宽度：视口比它窄时出现横向滚动。
    static let contentMinWidth: CGFloat = 520

    static let expandDuration: Double = 0.22
    static let hoverExpandDelay: Double = 0.12
    static let hoverCollapseDelay: Double = 0.35
    static let undoWindow: Double = 5
}
