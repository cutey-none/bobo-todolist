import AppKit
import SwiftUI

/// 真正的桌面毛玻璃（behindWindow），配合透明窗口使用。
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

/// 卡片类浅底，随系统浅色 / 深色自动适配。
struct CardBackground: View {
    var cornerRadius: CGFloat = 12
    var isHighlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(isHighlighted ? 0.92 : 0.68))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHighlighted ? Theme.accent.opacity(0.9) : Theme.hairline, lineWidth: isHighlighted ? 1.5 : 1)
            )
    }
}
