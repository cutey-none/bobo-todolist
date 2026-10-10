import AppKit
import SwiftUI

/// 展开态：顶栏 + 优先矩阵（UI PRD 4）。
struct PanelBodyView: View {
    @ObservedObject var state: AppState
    let today: Date
    let activeCounts: [Quadrant: Int]
    let completedCounts: [Quadrant: Int]
    let activeTasks: [Quadrant: [TaskItem]]
    let completedTasks: [Quadrant: [TaskItem]]
    let describedTaskIDs: Set<UUID>
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDrop: (String, Quadrant, Int?) -> Void
    let onCollapse: () -> Void
    let onWindowDragBegan: () -> Void
    let onWindowDrag: () -> Void
    let onWindowDragEnded: () -> Void

    @AppStorage("layout.columnFraction") private var columnFraction = 0.5
    @AppStorage("layout.topRowFraction") private var topRowFraction = 0.5
    @State private var splitDragStart: Double?
    @State private var windowDragging = false
    @FocusState private var focusedInput: Quadrant?

    private var totalActive: Int { activeCounts.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            quadrantScroll
        }
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: focusedInput) { _, quadrant in
            state.focusedInput = quadrant
            if let quadrant { state.selectedQuadrant = quadrant }
        }
        .onChange(of: state.inputFocusRequest) { _, request in
            if let request { focusedInput = request.quadrant }
        }
    }

    /// 内容区整体纵向滚动；按主内容可用宽度在 2×2 与单列之间切换。
    private var quadrantScroll: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - Metrics.contentPadding * 2
            let columns = available >= Metrics.matrixBreakpoint ? 2 : 1
            ScrollView(.vertical, showsIndicators: true) {
                matrix(columns: columns,
                       compact: columns == 2 && available / 2 < Metrics.compactQuadrantWidth,
                       minimumHeight: max(0, proxy.size.height - Metrics.contentPadding * 2))
                    .padding(Metrics.contentPadding)
            }
        }
    }

    private func matrix(columns: Int, compact: Bool, minimumHeight: CGFloat) -> some View {
        MatrixLayout(columns: columns, columnFraction: columnFraction,
                     topRowFraction: topRowFraction, minimumHeight: minimumHeight) {
            ForEach(Array(Quadrant.allCases.enumerated()), id: \.element) { index, quadrant in
                QuadrantCardView(
                    quadrant: quadrant,
                    isCompact: compact,
                    isHighlighted: state.highlightedQuadrant == quadrant,
                    activeTasks: activeTasks[quadrant] ?? [],
                    completedTasks: completedTasks[quadrant] ?? [],
                    describedTaskIDs: describedTaskIDs,
                    expandedTaskID: state.expandedTaskID,
                    focusedTaskID: state.focusedTaskID,
                    pendingTaskIDs: state.pendingCompletionIDs,
                    onToggle: onToggle,
                    onToggleExpand: { state.toggleExpanded($0) },
                    onEdit: onEdit,
                    onDelete: { task in withAnimation(.easeOut(duration: 0.18)) { _ = state.delete(task) } },
                    onMove: { task, quadrant in withAnimation(.easeOut(duration: 0.2)) { state.move(task, to: quadrant) } },
                    onReorder: { task, delta in withAnimation(.easeOut(duration: 0.2)) { state.reorder(task, by: delta) } },
                    draft: state.drafts[quadrant] ?? "",
                    inputProblem: state.inputProblems[quadrant],
                    inputFocus: $focusedInput,
                    onDraftChange: { state.updateDraft($0, in: quadrant) },
                    onSubmitDraft: { state.submitDraft(in: quadrant) },
                    onDrop: { raw, index in onDrop(raw, quadrant, index) },
                    onDragStateChange: { dragging in
                        if dragging { state.isDraggingTask = true }
                    }
                )
                .overlay(alignment: .bottom) {
                    if columns == 1, index < Quadrant.allCases.count - 1 {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
                .anchorPreference(key: MatrixTopRowBoundsKey.self, value: .bounds) { anchor in
                    columns == 2 && index == 0 ? anchor : nil
                }
            }
        }
        .overlayPreferenceValue(MatrixTopRowBoundsKey.self) { anchor in
            if columns == 2, let anchor {
                GeometryReader { proxy in
                    let left = MatrixLayout.leftWidth(total: proxy.size.width, fraction: columnFraction)
                    let top = proxy[anchor].maxY
                    ZStack(alignment: .topLeading) {
                        splitDivider(vertical: true, length: proxy.size.height, extent: proxy.size.width)
                            .offset(x: left - 4)
                        splitDivider(vertical: false, length: proxy.size.width, extent: proxy.size.height)
                            .offset(y: top - 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .coordinateSpace(name: "quadrant-matrix")
        .background(MatrixReadingSurface())
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.divider, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func splitDivider(vertical: Bool, length: CGFloat, extent: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: vertical ? 1 : length, height: vertical ? length : 1)
            .frame(width: vertical ? 8 : length, height: vertical ? length : 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() }
                else { NSCursor.arrow.set() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("quadrant-matrix"))
                .onChanged { value in
                    if splitDragStart == nil {
                        splitDragStart = vertical ? columnFraction : topRowFraction
                        state.isDraggingTask = true
                    }
                    let delta = vertical ? value.translation.width : value.translation.height
                    let fraction = min(0.8, max(0.2, (splitDragStart ?? 0.5) + delta / max(1, extent)))
                    if vertical { columnFraction = fraction } else { topRowFraction = fraction }
                }
                .onEnded { _ in
                    splitDragStart = nil
                    state.isDraggingTask = false
                })
            .accessibilityElement()
            .accessibilityLabel(vertical ? "调整左右象限宽度" : "调整上下象限高度")
            .accessibilityValue("\(Int((vertical ? columnFraction : topRowFraction) * 100))%")
            .accessibilityAdjustableAction { direction in
                let change = direction == .increment ? 0.05 : -0.05
                if vertical { columnFraction = min(0.8, max(0.2, columnFraction + change)) }
                else { topRowFraction = min(0.8, max(0.2, topRowFraction + change)) }
            }
    }

    private var header: some View {
        // 小浮窗里只留一行标题：名称 · 日期 …… 未完成数 · 收起。
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("优先矩阵")
                .font(.system(size: 16, weight: .bold))
            Text(Self.dateText(today))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            // 只统计未完成事项。
            Text("\(totalActive) 个待办")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize()

            Button(action: onCollapse) {
                Text("收起")
                    .font(.system(size: 11))
                    .padding(.horizontal, 3)
            }
            .liquidGlassButton()
            .help("收起为贴边条（Esc）")
        }
        .padding(.horizontal, Metrics.contentPadding + 2)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // SwiftUI 内容会覆盖 NSPanel 的 background-drag 命中区，因此标题栏
        // 显式桥接到 PanelController，保证展开后的整个 App 可以被拖动。
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in
                    if !windowDragging {
                        windowDragging = true
                        onWindowDragBegan()
                    }
                    onWindowDrag()
                }
                .onEnded { _ in
                    windowDragging = false
                    onWindowDragEnded()
                }
        )
        .help("拖动标题栏移动面板；移到屏幕边缘后松手可吸附")
    }

    /// 顶栏系统日期，例如「10月6日 · 周二」。
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEE"
        return formatter.string(from: date)
    }
}

private struct MatrixTopRowBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
