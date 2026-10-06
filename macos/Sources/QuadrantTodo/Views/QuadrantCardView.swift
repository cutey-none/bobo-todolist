import SwiftUI

/// 单个象限：标题与未完成数、细线分隔的任务行、默认折叠的已完成区（UI PRD 4.1）。
struct QuadrantCardView: View {
    let quadrant: Quadrant
    var isCompact = false
    let activeTasks: [TaskItem]
    let completedTasks: [TaskItem]
    let describedTaskIDs: Set<UUID>
    let expandedTaskID: UUID?
    let focusedTaskID: UUID?
    let pendingTaskIDs: Set<UUID>
    let onToggle: (TaskItem) -> Void
    let onToggleExpand: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onMove: (TaskItem, Quadrant) -> Void
    let onReorder: (TaskItem, Int) -> Void
    let draft: String
    let inputProblem: String?
    var inputFocus: FocusState<Quadrant?>.Binding
    let onDraftChange: (String) -> Void
    let onSubmitDraft: () -> Void
    let onDrop: (String, Int?) -> Void
    let onDragStateChange: (Bool) -> Void

    @State private var doneExpanded = false
    @State private var isTargeted = false
    @State private var targetedTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            if !activeTasks.isEmpty {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    TaskRowView(
                        task: task,
                        hasDescription: describedTaskIDs.contains(task.id),
                        isExpanded: expandedTaskID == task.id,
                        isPending: pendingTaskIDs.contains(task.id),
                        isFocused: focusedTaskID == task.id,
                        isTargeted: targetedTaskID == task.id,
                        onToggle: { onToggle(task) },
                        onToggleExpand: { onToggleExpand(task) },
                        onEdit: { onEdit(task) },
                        onMove: { onMove(task, $0) },
                        onReorder: { onReorder(task, $0) },
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
                    Divider().overlay(Theme.divider)
                }
            }
            QuadrantInputRow(
                quadrant: quadrant,
                // 空象限不再单独显示「暂无待办」，直接由输入行说明。
                placeholder: activeTasks.isEmpty ? "这个象限还没有待办，直接输入…" : "输入新待办…",
                text: draft,
                problem: inputProblem,
                focus: inputFocus,
                onChange: onDraftChange,
                onSubmit: onSubmitDraft
            )
            if !completedTasks.isEmpty { completedSection }
        }
        .padding(.horizontal, isCompact ? 12 : 20)
        .padding(.top, isCompact ? 10 : 14)
        .padding(.bottom, isCompact ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isTargeted ? Theme.accent.opacity(0.06) : .clear)
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
        .accessibilityLabel("\(quadrant.name)，\(activeTasks.count) 项待办")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(quadrant.name)
                .font(.system(size: 13, weight: .semibold))
            Text("· \(quadrant.hint)")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 4)
            // 只统计未完成事项；已完成数量在折叠入口里单独显示。
            Text("\(activeTasks.count)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
        .padding(.bottom, 10)
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Theme.divider).padding(.bottom, 4)
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
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("已完成 \(completedTasks.count) 项，\(doneExpanded ? "收起" : "展开")")

            if doneExpanded {
                ForEach(completedTasks) { task in
                    TaskRowView(
                        task: task,
                        hasDescription: describedTaskIDs.contains(task.id),
                        isExpanded: expandedTaskID == task.id,
                        isPending: pendingTaskIDs.contains(task.id),
                        isFocused: focusedTaskID == task.id,
                        isTargeted: false,
                        onToggle: { onToggle(task) },
                        onToggleExpand: { onToggleExpand(task) },
                        onEdit: { onEdit(task) },
                        onDropBefore: { _ in false },
                        onTargeted: { _ in }
                    )
                    Divider().overlay(Theme.divider)
                }
            }
        }
        .padding(.top, 12)
    }
}
