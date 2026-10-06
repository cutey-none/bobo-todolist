import SwiftUI

/// 任务卡片：勾选框 + 标题 + 悬停操作（PRD 4.6）。单击展开查看描述，双击打开编辑弹框。
struct TaskRowView: View {
    let task: TaskItem
    var hasDescription = false
    var isExpanded = false
    let isFocused: Bool
    let isTargeted: Bool
    let onToggle: () -> Void
    var onToggleExpand: () -> Void = {}
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDropBefore: ([String]) -> Bool
    let onTargeted: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded { details }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        // 双击优先识别，未构成双击时才按单击展开 / 收起。
        .gesture(
            TapGesture(count: 2).onEnded(onEdit)
                .exclusively(before: TapGesture().onEnded {
                    withAnimation(.easeOut(duration: 0.18)) { onToggleExpand() }
                })
        )
        .onHover { hovering = $0 }
        // 悬停行内任意位置都能看到完整文本（标题截断时尤其有用）。
        .help(tooltipText)
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .dropDestination(for: String.self) { items, _ in
            onDropBefore(items)
        } isTargeted: { targeted in
            onTargeted(targeted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .accessibilityAction(named: "展开描述") { onToggleExpand() }
        .accessibilityAction(named: "编辑") { onEdit() }
    }

    private var rowFill: Color {
        if isFocused { return Theme.accent.opacity(0.12) }
        if isExpanded { return Color.primary.opacity(0.045) }
        return hovering ? Color.primary.opacity(0.05) : .clear
    }

    @ViewBuilder private var details: some View {
        Group {
            if hasDescription {
                MarkdownView(markdown: task.note ?? "", fontSize: 12, imageMaxHeight: 140)
            } else {
                Text("暂无描述，双击编辑")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.leading, 31)
        .padding(.trailing, 10)
        .padding(.top, 2)
        .padding(.bottom, 9)
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(task.isCompleted ? task.quadrant.color : task.quadrant.color.opacity(0.75), lineWidth: 1.4)
                        .frame(width: 15, height: 15)
                    if task.isCompleted {
                        Circle().fill(task.quadrant.color).frame(width: 15, height: 15)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "取消完成 \(task.title)" : "完成 \(task.title)")

            Text(task.title)
                .font(.system(size: 12.5))
                .foregroundStyle(task.isCompleted ? AnyShapeStyle(Theme.secondaryText) : AnyShapeStyle(.primary))
                .strikethrough(task.isCompleted, color: Theme.secondaryText)
                .lineLimit(isExpanded ? nil : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasDescription {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundStyle(isExpanded ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.secondaryText))
                    .fixedSize()
            }

            if hovering || isFocused {
                Menu {
                    Button("编辑…", action: onEdit)
                    Divider()
                    Button("删除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 14)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .padding(.vertical, isExpanded ? 4 : 0)
    }

    private var tooltipText: String {
        var lines = [task.title]
        let description = MarkdownDocument.plainText(task.note ?? "")
        if !description.isEmpty {
            let limit = 120
            lines.append(description.count > limit ? String(description.prefix(limit)) + "…" : description)
        }
        lines.append(task.isCompleted ? "\(task.quadrant.name) · 已完成" : task.quadrant.name)
        lines.append("单击展开 · 双击编辑")
        return lines.joined(separator: "\n")
    }
}
