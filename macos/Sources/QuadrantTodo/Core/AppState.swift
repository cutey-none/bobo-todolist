import AppKit
import Combine
import SwiftUI

struct UndoEntry: Identifiable {
    let id = UUID()
    let snapshot: TaskSnapshot
    let title: String
}

struct InputFocusRequest: Equatable {
    let quadrant: Quadrant
    let serial: Int
}

/// 短暂、非阻塞的操作反馈；失败提示停留更久，可附带一个「撤销」之类的动作。
struct Notice: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (lhs: Notice, rhs: Notice) -> Bool { lhs.id == rhs.id }
}

/// 界面层共享状态：面板开合、草稿、输入焦点、撤销等。
@MainActor
final class AppState: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    /// 各象限尾部输入行的未提交草稿；放在共享状态里，跨布局切换不会丢失。
    @Published var drafts: [Quadrant: String] = [:]
    /// 输入行的校验或保存失败提示。
    @Published var inputProblems: [Quadrant: String] = [:]
    /// 当前获得焦点的输入行（由视图同步）。
    @Published var focusedInput: Quadrant?
    /// 最近使用的输入行：全局快捷键 / ⌘N 聚焦到这里。
    @Published var selectedQuadrant: Quadrant = .importantUrgent
    /// 快捷键聚焦时短暂高亮的象限，让用户知道新事项会加到哪里。
    @Published private(set) var highlightedQuadrant: Quadrant?
    @Published var editing: TaskItem?
    @Published var imagePreview: Data?
    @Published var editorCloseRequest = 0
    /// 可逐项撤销的删除队列，末尾是最新删除的事项。
    @Published private(set) var undoQueue: [UndoEntry] = []
    @Published private(set) var notice: Notice?
    @Published var focusedTaskID: UUID?
    /// 主界面中展开查看描述的事项：同一时刻只展开一个，含已完成区（UI PRD 5.1 建议默认）。
    @Published var expandedTaskID: UUID?
    @Published var isDraggingTask = false
    /// 正在保存完成状态的事项：保存结束前禁止重复点击（UI PRD 5.2）。
    @Published private(set) var pendingCompletionIDs: Set<UUID> = []
    /// 请求某个输入行获得焦点（每次自增都会让视图重新获取焦点）。
    @Published private(set) var inputFocusRequest: InputFocusRequest?

    weak var controller: PanelController?

    private let persistence: PersistenceController
    let settings: SettingsStore

    init(persistence: PersistenceController, settings: SettingsStore) {
        self.persistence = persistence
        self.settings = settings
    }

    var repository: TaskRepository { persistence.repository }

    // MARK: - 面板开合

    func expand(focusInput: Bool = false) {
        guard !isExpanded else {
            if focusInput { self.focusInput(selectedQuadrant) }
            return
        }
        isExpanded = true
        controller?.panel.orderFrontRegardless()
        if focusInput {
            self.focusInput(selectedQuadrant)
        } else {
            controller?.focusPanelIfNeeded()
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isPinned = false
        isExpanded = false
        focusedTaskID = nil
    }

    func toggle(focusInput: Bool = false) {
        if isExpanded {
            collapse()
        } else {
            expand(focusInput: focusInput)
        }
    }

    func focusInput(_ quadrant: Quadrant) {
        selectedQuadrant = quadrant
        expand()
        controller?.focusPanelIfNeeded()
        // 等窗口真正成为 key window 后再要焦点，否则 SwiftUI 的焦点会被丢弃。
        DispatchQueue.main.async { [weak self] in
            let serial = (self?.inputFocusRequest?.serial ?? 0) + 1
            self?.inputFocusRequest = InputFocusRequest(quadrant: quadrant, serial: serial)
        }
        withAnimation(.easeOut(duration: 0.15)) { highlightedQuadrant = quadrant }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard self?.highlightedQuadrant == quadrant else { return }
            withAnimation(.easeOut(duration: 0.4)) { self?.highlightedQuadrant = nil }
        }
    }

    /// 有未提交的输入草稿时保持面板展开，避免打断录入。
    var hasUnsubmittedDraft: Bool {
        drafts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - 任务操作

    /// 输入行内容变化：粘贴的换行转空格，超长时立即提示（不截断）。
    func updateDraft(_ text: String, in quadrant: Quadrant) {
        let single = TaskTitle.singleLine(text)
        drafts[quadrant] = single
        if case .failure(.tooLong) = TaskTitle.validate(single) {
            inputProblems[quadrant] = TaskTitle.Problem.tooLong.message
        } else {
            inputProblems[quadrant] = nil
        }
    }

    /// Enter 提交：保存成功后追加到该象限末尾、清空并保持焦点；失败时保留文本。
    func submitDraft(in quadrant: Quadrant) {
        switch TaskTitle.validate(drafts[quadrant] ?? "") {
        case .failure(let problem):
            inputProblems[quadrant] = problem.message
        case .success(let title):
            guard repository.addTask(title: title, quadrant: quadrant, to: repository.allTasks()) != nil else {
                inputProblems[quadrant] = "保存失败，请重试"
                return
            }
            // 新事项直接出现在列表末尾，无需再弹提示。
            drafts[quadrant] = ""
            inputProblems[quadrant] = nil
        }
        selectedQuadrant = quadrant
    }

    /// Esc：清空当前输入行的未提交草稿，保留焦点。返回是否有内容被清空。
    func clearDraft(in quadrant: Quadrant) -> Bool {
        let hadContent = !(drafts[quadrant] ?? "").isEmpty || inputProblems[quadrant] != nil
        drafts[quadrant] = ""
        inputProblems[quadrant] = nil
        return hadContent
    }

    /// 最新一次可撤销的删除。
    var undo: UndoEntry? { undoQueue.last }

    @discardableResult
    func delete(_ task: TaskItem) -> Bool {
        let title = task.title
        let id = task.id
        guard let snapshot = repository.delete(task) else {
            show("删除失败，请重试", isError: true)
            return false
        }
        let entry = UndoEntry(snapshot: snapshot, title: title)
        undoQueue.append(entry)
        // 每项删除有各自的撤销窗口，撤销一项不影响其他项的剩余时间。
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.undoWindow) { [weak self] in
            self?.expireUndo(entry.id)
        }
        if focusedTaskID == id { focusedTaskID = nil }
        if expandedTaskID == id { expandedTaskID = nil }
        return true
    }

    func performUndo() {
        guard let entry = undoQueue.last else { return }
        guard repository.restore(entry.snapshot) else {
            show("撤销失败，请重试", isError: true)
            return
        }
        undoQueue.removeAll { $0.id == entry.id }
    }

    private func expireUndo(_ id: UUID) {
        undoQueue.removeAll { $0.id == id }
        // 所有撤销窗口都结束后，旧 progress 记录才不再需要保留。
        if undoQueue.isEmpty { repository.purgeOrphanProgress() }
    }

    func show(_ text: String, isError: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let notice = Notice(text: text, isError: isError, actionTitle: actionTitle, action: action)
        self.notice = notice
        // 带「撤销」的提示多留一会儿，给用户反应时间。
        let duration: Double = action != nil ? 5 : (isError ? 4 : 1.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }

    /// 先进入 pending，下一轮 runloop 写入本地；只有保存成功才移动到已完成区或恢复未完成。
    func toggleCompletion(_ task: TaskItem) {
        guard !pendingCompletionIDs.contains(task.id) else { return }
        pendingCompletionIDs.insert(task.id)
        let before = CompletionState(task)
        let title = task.title
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let saved = withAnimation(.easeOut(duration: 0.18)) { self.repository.toggleCompletion(task) }
            self.pendingCompletionIDs.remove(task.id)
            guard saved else {
                self.show("保存失败，「\(title)」保持原状态", isError: true)
                return
            }
            // 完成后事项会折叠进已完成区，误点时需要一步撤销；恢复未完成肉眼可见，不再提示。
            guard !before.isCompleted else { return }
            self.show("已完成「\(title)」", actionTitle: "撤销") { [weak self] in
                self?.undoCompletion(task, to: before)
            }
        }
    }

    private func undoCompletion(_ task: TaskItem, to before: CompletionState) {
        let restored = withAnimation(.easeOut(duration: 0.18)) { repository.restoreCompletion(task, to: before) }
        notice = nil
        if !restored { show("撤销失败，请重试", isError: true) }
    }

    /// 键盘等价的「移至象限」：插入到目标象限顶部，失败时保持原象限与顺序。
    func move(_ task: TaskItem, to quadrant: Quadrant) {
        if !repository.move(task, to: quadrant) { show("移动失败，请重试", isError: true) }
    }

    func reorder(_ task: TaskItem, by delta: Int) {
        if !repository.reorder(task, by: delta) { show("移动失败，请重试", isError: true) }
    }

    /// 展开另一事项时自动收起当前事项；再次点击当前事项收起。
    func toggleExpanded(_ task: TaskItem) {
        expandedTaskID = expandedTaskID == task.id ? nil : task.id
    }

    func requestEditorClose() {
        editorCloseRequest += 1
    }

    // MARK: - 键盘选择

    func moveFocus(in quadrant: Quadrant, tasks: [TaskItem], delta: Int) {
        guard !tasks.isEmpty else { focusedTaskID = nil; return }
        guard let current = focusedTaskID, let index = tasks.firstIndex(where: { $0.id == current }) else {
            focusedTaskID = tasks.first?.id
            return
        }
        let next = min(max(index + delta, 0), tasks.count - 1)
        focusedTaskID = tasks[next].id
    }

    func selectQuadrant(_ quadrant: Quadrant) {
        selectedQuadrant = quadrant
    }

    func focusedTask(_ tasks: [TaskItem]) -> TaskItem? {
        guard let id = focusedTaskID else { return nil }
        return tasks.first { $0.id == id }
    }
}
