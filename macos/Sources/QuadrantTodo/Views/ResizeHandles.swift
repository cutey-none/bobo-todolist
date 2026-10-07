import AppKit
import SwiftUI

/// 展开面板四边与四角的隐形调整区：鼠标移到面板边缘时显示调整大小光标，按住拖动即可改变窗口尺寸。
/// 贴边停靠时，贴着屏幕的那一边（及其两角）不提供调整区。
struct ResizeHandles: View {
    let dockedEdge: EdgeSide?
    let onBegin: (ResizeEdges) -> Void
    let onDrag: () -> Void
    let onEnd: () -> Void

    /// 窗口透明边距再向面板内多伸 4pt，鼠标在可见边缘内外都能抓到。
    private let thickness = Metrics.panelInset + 4
    private let corner: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                handle(.left, width: thickness, height: size.height - corner * 2, x: 0, y: corner)
                handle(.right, width: thickness, height: size.height - corner * 2, x: size.width - thickness, y: corner)
                handle(.top, width: size.width - corner * 2, height: thickness, x: corner, y: 0)
                handle(.bottom, width: size.width - corner * 2, height: thickness, x: corner, y: size.height - thickness)
                handle([.top, .left], width: corner, height: corner, x: 0, y: 0)
                handle([.top, .right], width: corner, height: corner, x: size.width - corner, y: 0)
                handle([.bottom, .left], width: corner, height: corner, x: 0, y: size.height - corner)
                handle([.bottom, .right], width: corner, height: corner, x: size.width - corner, y: size.height - corner)
            }
        }
    }

    @ViewBuilder
    private func handle(_ edges: ResizeEdges, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        if edges.isDisjoint(with: blockedEdges) {
            ResizeHandleRepresentable(edges: edges, onBegin: onBegin, onDrag: onDrag, onEnd: onEnd)
                .frame(width: max(0, width), height: max(0, height))
                .offset(x: x, y: y)
        }
    }

    private var blockedEdges: ResizeEdges {
        switch dockedEdge {
        case .left: return .left
        case .right: return .right
        case .top: return .top
        case .bottom: return .bottom
        case nil: return []
        }
    }
}

private struct ResizeHandleRepresentable: NSViewRepresentable {
    let edges: ResizeEdges
    let onBegin: (ResizeEdges) -> Void
    let onDrag: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        update(view)
        return view
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) { update(view) }

    private func update(_ view: ResizeHandleView) {
        view.edges = edges
        view.onBegin = onBegin
        view.onDrag = onDrag
        view.onEnd = onEnd
    }
}

/// 直接处理鼠标事件，不经过 SwiftUI 手势：位移由 PanelController 按屏幕坐标计算，窗口变化不会反过来干扰。
final class ResizeHandleView: NSView {
    var edges: ResizeEdges = [] { didSet { window?.invalidateCursorRects(for: self) } }
    var onBegin: (ResizeEdges) -> Void = { _ in }
    var onDrag: () -> Void = {}
    var onEnd: () -> Void = {}
    private var tracking: NSTrackingArea?

    // 面板不抢焦点：第一次点击就要能开始调整。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // 面板是不激活应用的浮窗，必须 activeAlways，否则应用在后台时光标不会变化。
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) { onBegin(edges) }
    override func mouseDragged(with event: NSEvent) { cursor.set(); onDrag() }
    override func mouseUp(with event: NSEvent) { onEnd() }

    private var cursor: NSCursor {
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        if horizontal && vertical {
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition = switch (edges.contains(.top), edges.contains(.left)) {
                case (true, true): .topLeft
                case (true, false): .topRight
                case (false, true): .bottomLeft
                case (false, false): .bottomRight
                }
                return NSCursor.frameResize(position: position, directions: .all)
            }
            return .crosshair
        }
        return horizontal ? .resizeLeftRight : .resizeUpDown
    }
}
