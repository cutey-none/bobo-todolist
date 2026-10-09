import AppKit
import SwiftUI

/// Track hover even when another application is active and this floating panel
/// has not taken keyboard focus. The tracking view never consumes clicks.
struct TaskTitleHoverRegion: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TaskTitleHoverView {
        let view = TaskTitleHoverView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TaskTitleHoverView, context: Context) {
        view.onHover = onHover
    }
}

final class TaskTitleHoverView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

struct TaskTitleTooltip {
    let title: String
    let bounds: Anchor<CGRect>
}

struct TaskTitleTooltipKey: PreferenceKey {
    static var defaultValue: TaskTitleTooltip? { nil }

    static func reduce(value: inout TaskTitleTooltip?, nextValue: () -> TaskTitleTooltip?) {
        value = nextValue() ?? value
    }
}

/// Render above the scroll view so a full title is never clipped by its quadrant.
/// Explicit hover feedback also works in the nonactivating panel, without waiting
/// for AppKit's delayed help tag or changing keyboard focus.
struct TaskTitleTooltipOverlay: View {
    let tooltip: TaskTitleTooltip?

    var body: some View {
        GeometryReader { proxy in
            if let tooltip {
                let rect = proxy[tooltip.bounds]
                let width = min(440, max(0, proxy.size.width - 48))
                let x = min(max(24, rect.minX), proxy.size.width - width - 24)
                let above = rect.midY > proxy.size.height / 2
                Text(tooltip.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(width: width, alignment: .leading)
                    .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.divider))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .frame(height: above ? max(0, rect.minY - 8) : nil, alignment: .bottom)
                    .offset(x: x, y: above ? 0 : rect.maxY + 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
