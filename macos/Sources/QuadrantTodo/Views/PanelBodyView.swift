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
    let onDelete: (TaskItem) -> Void
    let onAdd: (Quadrant) -> Void
    let onDrop: (String, Quadrant, Int?) -> Void
    let onCollapse: () -> Void
    let onSubmitDraft: () -> Void
    let onWindowDragBegan: () -> Void
    let onWindowDrag: () -> Void
    let onWindowDragEnded: () -> Void

    @State private var windowDragging = false

    private var totalActive: Int { activeCounts.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            quadrantScroll
            Divider().overlay(Theme.hairline)
            footer
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panelBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 内容区整体纵向滚动；按主内容可用宽度在 2×2 与单列之间切换。
    private var quadrantScroll: some View {
        GeometryReader { proxy in
            let columns = proxy.size.width - Metrics.contentPadding * 2 >= Metrics.matrixBreakpoint ? 2 : 1
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    matrixHeading
                    matrix(columns: columns)
                }
                .padding(Metrics.contentPadding)
            }
        }
    }

    private var matrixHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("优先矩阵")
                .font(.system(size: 16, weight: .bold))
            Spacer(minLength: 8)
            Text("\(totalActive) 个待办")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private func matrix(columns: Int) -> some View {
        MatrixLayout(columns: columns) {
            ForEach(Array(Quadrant.allCases.enumerated()), id: \.element) { index, quadrant in
                QuadrantCardView(
                    quadrant: quadrant,
                    activeTasks: activeTasks[quadrant] ?? [],
                    completedTasks: completedTasks[quadrant] ?? [],
                    describedTaskIDs: describedTaskIDs,
                    expandedTaskIDs: state.expandedTaskIDs,
                    focusedTaskID: state.focusedTaskID,
                    onToggle: onToggle,
                    onToggleExpand: { state.toggleExpanded($0) },
                    onEdit: onEdit,
                    onDelete: onDelete,
                    onAdd: onAdd,
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("四象限待办")
                .font(.system(size: 17, weight: .bold))
            Text(Self.dateText(today))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            Spacer(minLength: 4)

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

    private var footer: some View {
        VStack(spacing: 7) {
            if state.composerOpen {
                ComposerView(state: state, onSubmit: onSubmitDraft, onCancel: { state.composerOpen = false })
            }
            HStack(spacing: 7) {
                Button {
                    onAdd(state.selectedQuadrant)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("新建任务")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .help("新建任务（⌘N）")

                Button(action: onCollapse) {
                    Text("收起")
                        .font(.system(size: 12))
                        .frame(width: 46, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// 顶栏系统日期，例如「10月6日 · 周二」。
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEE"
        return formatter.string(from: date)
    }
}
