import SwiftUI

/// 单个象限卡片：未完成任务优先，已完成折叠到底部（PRD F3 / 4.2）。
struct QuadrantCardView: View {
    let quadrant: Quadrant
    let activeTasks: [TaskItem]
    let completedTasks: [TaskItem]
    let progressCounts: [UUID: Int]
    let focusedTaskID: UUID?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onAdd: (Quadrant) -> Void
    let onDrop: (String, Int?) -> Void
    let onDragStateChange: (Bool) -> Void

    @State private var doneExpanded = false
    @State private var isTargeted = false
    @State private var targetedTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if activeTasks.isEmpty {
                emptyPlaceholder
            } else {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    TaskRowView(
                        task: task,
                        progressCount: progressCounts[task.id, default: 0],
                        isFocused: focusedTaskID == task.id,
                        isTargeted: targetedTaskID == task.id,
                        onToggle: { withAnimation(.easeOut(duration: 0.18)) { onToggle(task) } },
                        onEdit: { onEdit(task) },
                        onDelete: { onDelete(task) },
                        onDropBefore: { items in
                            guard let raw = items.first else { return false }
                            onDrop(raw, index)
                            targetedTaskID = nil
                            return true
                        },
                        onTargeted: { targeted in
                            targetedTaskID = targeted ? task.id : nil
                        }
                    )
                }
            }
            if !completedTasks.isEmpty { completedSection }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(CardBackground(isHighlighted: isTargeted))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            onDrop(raw, nil)
            isTargeted = false
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
            if targeted { onDragStateChange(true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(quadrant.name)，\(activeTasks.count) 项未完成")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(quadrant.color).frame(width: 7, height: 7)
            Text(quadrant.name)
                .font(.system(size: 12, weight: .semibold))
            Button {
                onAdd(quadrant)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("在\(quadrant.name)新建任务")
            .opacity(0.85)
            Spacer(minLength: 4)
            Text("\(activeTasks.count) / \(activeTasks.count + completedTasks.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 3)
    }

    private var emptyPlaceholder: some View {
        Button {
            onAdd(quadrant)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "diamond")
                    .font(.system(size: 9))
                Text("暂无任务，点击添加")
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Theme.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { doneExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(doneExpanded ? 90 : 0))
                    Text("已完成 \(completedTasks.count)")
                        .font(.system(size: 11))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)
                .frame(height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("已完成 \(completedTasks.count) 项，\(doneExpanded ? "收起" : "展开")")

            if doneExpanded {
                ForEach(completedTasks) { task in
                    TaskRowView(
                        task: task,
                        progressCount: progressCounts[task.id, default: 0],
                        isFocused: focusedTaskID == task.id,
                        isTargeted: false,
                        onToggle: { withAnimation(.easeOut(duration: 0.18)) { onToggle(task) } },
                        onEdit: { onEdit(task) },
                        onDelete: { onDelete(task) },
                        onDropBefore: { _ in false },
                        onTargeted: { _ in }
                    )
                }
            }
        }
        .padding(.top, 1)
    }
}
