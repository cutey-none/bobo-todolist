import SwiftUI

/// 贴边收起态：四色图标 + 各象限未完成数 + 未完成总数（PRD 12.3）。
struct RailView: View {
    let counts: [Quadrant: Int]
    let total: Int
    let edge: EdgeSide
    let onHover: (Bool) -> Void
    let onDragBegan: () -> Void
    let onDrag: () -> Void
    let onDragEnded: () -> Void

    @State private var dragging = false

    var body: some View {
        Group {
            if edge.isVertical {
                VStack(spacing: 0) { Spacer(minLength: 0); content; Spacer(minLength: 0) }
                    .frame(width: Metrics.railWidth, height: Metrics.railHeight)
            } else {
                HStack(spacing: 0) { Spacer(minLength: 0); content; Spacer(minLength: 0) }
                    .frame(width: Metrics.railHeight, height: Metrics.railWidth)
            }
        }
        .background(railBackground)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in
                    if !dragging { dragging = true; onDragBegan() }
                    onDrag()
                }
                .onEnded { _ in dragging = false; onDragEnded() }
        )
        .help("悬停展开待办面板，拖到屏幕任意边缘可吸附")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("四象限待办，未完成 \(total) 项")
    }

    @ViewBuilder private var content: some View {
        if edge.isVertical { verticalContent } else { horizontalContent }
    }

    private var verticalContent: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 1)

            VStack(spacing: 9) {
                ForEach(Quadrant.allCases) { quadrant in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(quadrant.color)
                            .frame(width: 7, height: 7)
                        Text("\(counts[quadrant] ?? 0)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.top, 14)

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 18, height: 1)
                .padding(.vertical, 10)

            Text("\(total)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("未完成")
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var horizontalContent: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            ForEach(Quadrant.allCases) { quadrant in
                HStack(spacing: 3) {
                    Circle().fill(quadrant.color).frame(width: 7, height: 7)
                    Text("\(counts[quadrant] ?? 0)").font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
            Text("\(total)").font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    @ViewBuilder private var railBackground: some View {
        if edge.isVertical {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: edge == .right ? Metrics.railCorner : 0,
            bottomLeadingRadius: edge == .right ? Metrics.railCorner : 0,
            bottomTrailingRadius: edge == .right ? 0 : Metrics.railCorner,
            topTrailingRadius: edge == .right ? 0 : Metrics.railCorner,
            style: .continuous
        )
        shape
            .fill(.clear)
            .background(VisualEffectView(material: .popover).clipShape(shape))
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        } else {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: edge == .bottom ? Metrics.railCorner : 0,
                bottomLeadingRadius: edge == .top ? Metrics.railCorner : 0,
                bottomTrailingRadius: edge == .top ? Metrics.railCorner : 0,
                topTrailingRadius: edge == .bottom ? Metrics.railCorner : 0,
                style: .continuous
            )
            shape.fill(.clear)
                .background(VisualEffectView(material: .popover).clipShape(shape))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
