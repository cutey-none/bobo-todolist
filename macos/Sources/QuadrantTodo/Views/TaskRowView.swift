import SwiftUI

/// 任务卡片：勾选框 + 标题 + 悬停操作（PRD 4.6）。
struct TaskRowView: View {
    let task: TaskItem
    var hasDescription = false
    let isFocused: Bool
    let isTargeted: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDropBefore: ([String]) -> Bool
    let onTargeted: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
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

            Button(action: onEdit) {
                Text(task.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(task.isCompleted ? AnyShapeStyle(Theme.secondaryText) : AnyShapeStyle(.primary))
                    .strikethrough(task.isCompleted, color: Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasDescription {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
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
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isFocused ? Theme.accent.opacity(0.12) : (hovering ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
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
    }

    private var tooltipText: String {
        var lines = [task.title]
        let description = MarkdownDocument.plainText(task.note ?? "")
        if !description.isEmpty {
            let limit = 120
            lines.append(description.count > limit ? String(description.prefix(limit)) + "…" : description)
        }
        lines.append(task.isCompleted ? "\(task.quadrant.name) · 已完成" : task.quadrant.name)
        return lines.joined(separator: "\n")
    }
}
