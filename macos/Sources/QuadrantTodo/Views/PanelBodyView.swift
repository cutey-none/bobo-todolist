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

    @State private var windowDragging = false
    @FocusState private var focusedInput: Quadrant?

    private var totalActive: Int { activeCounts.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            quadrantScroll
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panelBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            let columns = proxy.size.width - Metrics.contentPadding * 2 >= Metrics.matrixBreakpoint ? 2 : 1
            ScrollView(.vertical, showsIndicators: true) {
                matrix(columns: columns)
                    .padding(Metrics.contentPadding)
            }
        }
    }

    private func matrix(columns: Int) -> some View {
        MatrixLayout(columns: columns) {
            ForEach(Array(Quadrant.allCases.enumerated()), id: \.element) { index, quadrant in
                QuadrantCardView(
                    quadrant: quadrant,
                    activeTasks: activeTasks[quadrant] ?? [],
                    completedTasks: completedTasks[quadrant] ?? [],
                    describedTaskIDs: describedTaskIDs,
                    expandedTaskID: state.expandedTaskID,
                    focusedTaskID: state.focusedTaskID,
                    pendingTaskIDs: state.pendingCompletionIDs,
                    onToggle: onToggle,
                    onToggleExpand: { state.toggleExpanded($0) },
                    onEdit: onEdit,
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
                .overlay(alignment: .trailing) {
                    if columns == 2, index % 2 == 0 { Rectangle().fill(Theme.divider).frame(width: 1) }
                }
                .overlay(alignment: .bottom) {
                    if index < Quadrant.allCases.count - columns { Rectangle().fill(Theme.divider).frame(height: 1) }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
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
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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
