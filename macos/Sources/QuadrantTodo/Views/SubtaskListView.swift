import SwiftData
import SwiftUI

private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    /// 主面板与编辑浮层注入的 AppState；独立渲染的任务行（如测试）没有子待办区。
    var appState: AppState? {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}

/// 子待办拖拽载荷：带前缀，事项的拖放目标解析不出 UUID，会忽略它。
enum SubtaskDrag {
    private static let prefix = "subtask:"

    static func payload(_ id: UUID) -> String { prefix + id.uuidString }

    static func id(from raw: String) -> UUID? {
        guard raw.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(prefix.count)))
    }
}

enum SubtaskField: Hashable {
    case add
    case rename(UUID)
}

/// 子待办列表（PRD 15）：主面板展开区与编辑浮层共用，所有修改立即保存。
struct SubtaskListView: View {
    let parentID: UUID
    let state: AppState
    @Query private var items: [SubtaskItem]

    @State private var draft = ""
    @State private var draftProblem: String?
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var editingProblem: String?
    @State private var cancellingID: UUID?
    @State private var targetedID: UUID?
    @State private var inputToken = UUID()
    @FocusState private var focus: SubtaskField?

    init(parentID: UUID, state: AppState) {
        self.parentID = parentID
        self.state = state
        let id = parentID
        _items = Query(
            filter: #Predicate<SubtaskItem> { $0.parentID == id },
            sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                SubtaskRowView(
                    item: item,
                    isEditing: editingID == item.id,
                    editingText: $editingText,
                    problem: editingID == item.id ? editingProblem : nil,
                    focus: $focus,
                    isTargeted: targetedID == item.id,
                    onToggle: { withAnimation(.easeOut(duration: 0.15)) { state.toggleSubtask(item) } },
                    onBeginEdit: { beginEdit(item) },
                    onCommitEdit: commitEdit,
                    onCancelEdit: cancelEdit,
                    onDelete: { withAnimation(.easeOut(duration: 0.15)) { state.deleteSubtask(item) } },
                    onPromote: { withAnimation(.easeOut(duration: 0.18)) { state.promoteSubtask(item) } },
                    onMove: { delta in withAnimation(.easeOut(duration: 0.15)) { state.moveSubtask(item, by: delta) } },
                    onDrop: { raw in drop(raw, before: item.id) },
                    onTargeted: { targetedID = $0 ? item.id : (targetedID == item.id ? nil : targetedID) }
                )
            }
            addRow
        }
        .onChange(of: hasPendingInput) { _, pending in
            if pending { state.activeSubtaskInputs.insert(inputToken) } else { state.activeSubtaskInputs.remove(inputToken) }
        }
        .onChange(of: focus) { old, new in
            if new != nil { state.focusedSubtaskInputs.insert(inputToken) } else { state.focusedSubtaskInputs.remove(inputToken) }
            // 改名输入框失焦即保存；Esc 取消引起的失焦除外。
            if case .rename(let id)? = old, new != old, editingID == id, cancellingID != id { commitEdit() }
        }
        .onAppear { draft = state.subtaskDrafts[parentID] ?? "" }
        .onChange(of: draft) { _, text in
            state.subtaskDrafts[parentID] = text.isEmpty ? nil : text
        }
        .onDisappear {
            // 行收起、事项移入已完成区或浮层关闭也算离开：保存正在进行的改名（草稿已存在 AppState）。
            if editingID != nil, cancellingID == nil { commitEdit() }
            state.activeSubtaskInputs.remove(inputToken)
            state.focusedSubtaskInputs.remove(inputToken)
        }
    }

    private var hasPendingInput: Bool {
        editingID != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 36)
                TextField("添加子待办…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focus, equals: .add)
                    .onSubmit(submitDraft)
                    .onExitCommand { draft = ""; draftProblem = nil }
                    .onChange(of: draft) { _, text in
                        draftProblem = TaskTitle.validate(text) == .failure(.tooLong) ? TaskTitle.Problem.tooLong.message : nil
                    }
                    .accessibilityLabel("添加子待办")
            }
            .frame(minHeight: 26)
            .dropDestination(for: String.self) { raws, _ in
                raws.first.map { drop($0, before: nil) } ?? false
            }
            if let draftProblem {
                Text(draftProblem)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.red)
                    .padding(.leading, 42)
            }
        }
    }

    private func submitDraft() {
        if let problem = state.addSubtask(draft, to: parentID) {
            draftProblem = problem
            return
        }
        draft = ""
        draftProblem = nil
        focus = .add
    }

    private func beginEdit(_ item: SubtaskItem) {
        if editingID != nil { commitEdit() }
        editingID = item.id
        editingText = item.title
        editingProblem = nil
        // 输入框在这次更新中才出现，下一轮再聚焦，焦点才能落到它上面。
        let id = item.id
        DispatchQueue.main.async { if editingID == id { focus = .rename(id) } }
    }

    private func commitEdit() {
        guard let id = editingID, let item = items.first(where: { $0.id == id }) else {
            editingID = nil
            return
        }
        if let problem = state.renameSubtask(item, to: editingText) {
            editingProblem = problem
            return
        }
        editingID = nil
        editingProblem = nil
    }

    /// 先在输入框仍存在时释放焦点，下一轮再移除输入框：若同时移除，SwiftUI 会丢掉这次焦点变化，
    /// 之后再点同一行改名时迟到地报告旧输入框失焦，把新开的改名当作保存关掉。
    private func cancelEdit() {
        guard let id = editingID else { return }
        cancellingID = id
        focus = nil
        DispatchQueue.main.async {
            if editingID == id { editingID = nil }
            editingProblem = nil
            cancellingID = nil
        }
    }

    /// 只接受同一父待办的子待办；事项或其他父待办的子待办一律拒绝。
    private func drop(_ raw: String, before targetID: UUID?) -> Bool {
        targetedID = nil
        guard let id = SubtaskDrag.id(from: raw), let item = items.first(where: { $0.id == id }) else { return false }
        guard id != targetID else { return true }
        withAnimation(.easeOut(duration: 0.15)) { state.moveSubtask(item, before: targetID) }
        return true
    }
}

/// 子待办行：圆圈只勾选；单击标题原地改名；垃圾桶删除；把手拖拽排序。
private struct SubtaskRowView: View {
    let item: SubtaskItem
    let isEditing: Bool
    @Binding var editingText: String
    let problem: String?
    var focus: FocusState<SubtaskField?>.Binding
    let isTargeted: Bool
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    let onPromote: () -> Void
    let onMove: (Int) -> Void
    let onDrop: (String) -> Bool
    let onTargeted: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                handle
                checkbox
                title
                Spacer(minLength: 4)
                deleteButton
            }
            .frame(minHeight: 26)
            if let problem {
                Text(problem)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.red)
                    .padding(.leading, 42)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.accent).frame(height: 1.5).opacity(isTargeted ? 1 : 0)
        }
        .dropDestination(for: String.self) { raws, _ in
            raws.first.map(onDrop) ?? false
        } isTargeted: { onTargeted($0) }
        .contextMenu {
            Button("上移") { onMove(-1) }
            Button("下移") { onMove(1) }
            Button("提升为独立待办", action: onPromote)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "上移") { onMove(-1) }
        .accessibilityAction(named: "下移") { onMove(1) }
        .accessibilityAction(named: "提升为独立待办", onPromote)
        .accessibilityAction(named: "删除", onDelete)
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Theme.tertiaryText)
            .frame(width: 10, height: 24)
            .contentShape(Rectangle())
            .opacity(hovering ? 1 : 0)
            .draggable(SubtaskDrag.payload(item.id)) {
                Text(item.title).font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 4)
            }
            .help("拖动以调整顺序")
            .accessibilityHidden(true)
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            ZStack {
                Circle().strokeBorder(Theme.secondaryText, lineWidth: 1.2)
                if item.isCompleted {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 13, height: 13)
            .frame(width: 20, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.isCompleted ? "恢复为未完成" : "标记完成")
        .accessibilityLabel(item.isCompleted ? "恢复未完成：\(item.title)" : "完成：\(item.title)")
    }

    @ViewBuilder private var title: some View {
        if isEditing {
            TextField("子待办", text: $editingText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(focus, equals: .rename(item.id))
                .onSubmit(onCommitEdit)
                .onExitCommand(perform: onCancelEdit)
                .accessibilityLabel("重命名子待办")
        } else {
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(item.isCompleted ? AnyShapeStyle(Theme.secondaryText) : AnyShapeStyle(.primary))
                .strikethrough(item.isCompleted, color: Theme.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onBeginEdit)
                .help("单击重命名")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "重命名", onBeginEdit)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0)
        .help("删除子待办（可撤销）")
        .accessibilityLabel("删除子待办：\(item.title)")
    }
}
