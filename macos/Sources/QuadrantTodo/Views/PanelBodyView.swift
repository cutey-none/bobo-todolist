import SwiftUI

/// 展开态：标题栏 + 四象限列表 + 底部新建 / 收起（PRD 12.3）。
struct PanelBodyView: View {
    @ObservedObject var state: AppState
    let activeCounts: [Quadrant: Int]
    let completedCounts: [Quadrant: Int]
    let activeTasks: [Quadrant: [TaskItem]]
    let completedTasks: [Quadrant: [TaskItem]]
    let progressCounts: [UUID: Int]
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onAdd: (Quadrant) -> Void
    let onDrop: (String, Quadrant, Int?) -> Void
    let onCollapse: () -> Void
    let onSubmitDraft: () -> Void
    let onWindowDragBegan: () -> Void
    let onWindowDrag: (CGSize) -> Void
    let onWindowDragEnded: () -> Void

    @State private var windowDragging = false

    private var totalActive: Int { activeCounts.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            quadrantScroll
            Divider().overlay(Theme.hairline)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.clear)
                .background(VisualEffectView(material: .popover).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 内容区：固定窗口尺寸下，纵向超出用滚轮滚动，横向超出可左右滚动。
    private var quadrantScroll: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(spacing: 7) {
                    ForEach(Quadrant.allCases) { quadrant in
                        QuadrantCardView(
                            quadrant: quadrant,
                            activeTasks: activeTasks[quadrant] ?? [],
                            completedTasks: completedTasks[quadrant] ?? [],
                            progressCounts: progressCounts,
                            focusedTaskID: state.focusedTaskID,
                            onToggle: onToggle,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onAdd: onAdd,
                            onDrop: { raw, index in onDrop(raw, quadrant, index) },
                            onDragStateChange: { dragging in
                                if dragging { state.isDraggingTask = true }
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                // 低于最小布局宽度时横向滚动，窗口更宽时自适应铺满。
                .frame(width: max(proxy.size.width, Metrics.contentMinWidth), alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)

            Text("待办事项")
                .font(.system(size: 14.5, weight: .semibold))

            Spacer(minLength: 4)

            Text("未完成")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            Text("\(totalActive)")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // SwiftUI 内容会覆盖 NSPanel 的 background-drag 命中区，因此标题栏
        // 显式桥接到 PanelController，保证展开后的整个 App 可以被拖动。
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !windowDragging {
                        windowDragging = true
                        onWindowDragBegan()
                    }
                    onWindowDrag(value.translation)
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
}
