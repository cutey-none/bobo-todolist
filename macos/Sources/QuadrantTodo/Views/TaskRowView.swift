import SwiftUI

/// 任务行（UI PRD 5）：完成圆圈、标题、行空白 / 展开箭头各有独立且互不抢占的点击区域。
/// - 圆圈只切换完成状态；
/// - 标题及紧贴的小铅笔打开编辑浮层；
/// - 行空白与行尾箭头展开 / 收起 Markdown 描述；
/// - 拖拽只能从行空白发起，标题、圆圈、箭头与描述正文都不发起拖拽。
struct TaskRowView: View {
    let task: TaskItem
    var hasDescription = false
    var isExpanded = false
    var isPending = false
    let isFocused: Bool
    let isTargeted: Bool
    let onToggle: () -> Void
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    var onMove: (Quadrant) -> Void = { _ in }
    var onReorder: (Int) -> Void = { _ in }
    let onDropBefore: ([String]) -> Bool
    let onTargeted: (Bool) -> Void

    @State private var titleHovering = false
    @State private var rowHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded { details }
        }
        .background(rowFill)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .dropDestination(for: String.self) { items, _ in
            onDropBefore(items)
        } isTargeted: { targeted in
            onTargeted(targeted)
        }
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isExpanded ? "收起描述" : "展开描述") { onToggleExpand() }
        .accessibilityAction(named: "编辑") { onEdit() }
        .accessibilityAction(named: "上移") { onReorder(-1) }
        .accessibilityAction(named: "下移") { onReorder(1) }
    }

    private var rowFill: Color {
        if isFocused { return Theme.accent.opacity(0.10) }
        return isExpanded ? Theme.subtleFill : .clear
    }

    private var header: some View {
        HStack(spacing: 8) {
            dragHandle
            completionButton
            titleButton
            blankArea
            expandButton
        }
        .frame(minHeight: 40)
        .onHover { rowHovering = $0 }
    }

    private var completionButton: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .strokeBorder(task.quadrant.color.opacity(task.isCompleted ? 1 : 0.8), lineWidth: 1.4)
                if task.isCompleted {
                    Circle().fill(task.quadrant.color)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                if isPending {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 16, height: 16)
            .frame(width: 24, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 保存完成前禁止重复点击。
        .disabled(isPending)
        .help(task.isCompleted ? "恢复为未完成" : "标记完成")
        .accessibilityLabel(task.isCompleted ? "恢复未完成：\(task.title)" : "完成：\(task.title)")
        .accessibilityValue(isPending ? "正在保存" : (task.isCompleted ? "已完成" : "未完成"))
    }

    private var titleButton: some View {
        Button(action: onEdit) {
            HStack(spacing: 5) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted ? AnyShapeStyle(Theme.secondaryText) : AnyShapeStyle(.primary))
                    .strikethrough(task.isCompleted, color: Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if titleHovering || isFocused {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(titleHovering || isFocused ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 标题优先占宽度，行空白只拿剩余部分；放不下时才截断。
        .layoutPriority(1)
        .onHover { titleHovering = $0 }
        .help(tooltipText)
        .accessibilityLabel("编辑：\(task.title)")
    }

    /// 标题之外的行空白：单击展开，按住移动超过系统拖拽阈值才开始拖拽。
    private var blankArea: some View {
        // 固定高度：象限按行对齐拉高时，多余空间留在象限底部而不是撑高任务行。
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpand() }
            .modifier(RowDragSource(task: task, isEnabled: !task.isCompleted))
            .accessibilityHidden(true)
    }

    /// 悬停时出现的拖拽把手，让「可以拖」被看见；已完成事项不显示。
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Theme.tertiaryText)
            .frame(width: 12, height: 32)
            .contentShape(Rectangle())
            .opacity(rowHovering && !task.isCompleted ? 1 : 0)
            .modifier(RowDragSource(task: task, isEnabled: !task.isCompleted))
            .help("拖动以排序或移到其他象限")
            .accessibilityHidden(true)
    }

    /// 有描述的行常显箭头（也代替原来的描述图标）；没有描述时只在悬停或展开时出现，
    /// 隐藏时仍可点击，与行空白的行为一致。
    private var expandButton: some View {
        Button(action: toggleExpand) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 28, minHeight: 32)
                .contentShape(Rectangle())
                .opacity(hasDescription || isExpanded || rowHovering || isFocused ? 1 : 0)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "收起描述" : "展开描述")
        .accessibilityLabel(isExpanded ? "收起描述" : "展开描述")
    }

    @ViewBuilder private var details: some View {
        Group {
            if hasDescription {
                MarkdownView(markdown: task.note ?? "", fontSize: 12, imageMaxHeight: 140)
                    // 选中正文、点链接不会反向触发展开或编辑：这些手势只挂在标题与行空白上。
                    .textSelection(.enabled)
            } else {
                Text("暂无描述")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.leading, 57)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .transition(.opacity)
    }

    @ViewBuilder private var menu: some View {
        Button("编辑…", action: onEdit)
        Button(isExpanded ? "收起描述" : "展开描述", action: toggleExpand)
        if !task.isCompleted {
            Divider()
            Menu("移至象限") {
                ForEach(Quadrant.allCases.filter { $0 != task.quadrant }) { quadrant in
                    Button(quadrant.name) { onMove(quadrant) }
                }
            }
            Button("上移") { onReorder(-1) }
            Button("下移") { onReorder(1) }
        }
    }

    private func toggleExpand() {
        withAnimation(.easeOut(duration: 0.18)) { onToggleExpand() }
    }

    private var tooltipText: String {
        var lines = [task.title]
        let description = MarkdownDocument.plainText(task.note ?? "")
        if !description.isEmpty {
            let limit = 120
            lines.append(description.count > limit ? String(description.prefix(limit)) + "…" : description)
        }
        lines.append(task.isCompleted ? "\(task.quadrant.name) · 已完成" : task.quadrant.name)
        lines.append("单击标题编辑 · 单击空白处展开描述")
        return lines.joined(separator: "\n")
    }
}

/// 已完成事项不参与拖拽排序（UI PRD 8）。
private struct RowDragSource: ViewModifier {
    let task: TaskItem
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(task.id.uuidString) {
                Text(task.title)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        } else {
            content
        }
    }
}
