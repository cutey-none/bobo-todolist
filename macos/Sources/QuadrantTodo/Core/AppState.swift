import AppKit
import Combine
import SwiftUI

struct UndoEntry: Identifiable {
    let id = UUID()
    let snapshot: TaskSnapshot
    let title: String
}

/// 短暂、非阻塞的操作反馈；失败提示停留更久。
struct Notice: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// 界面层共享状态：面板开合、草稿、输入焦点、撤销等。
@MainActor
final class AppState: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var draft = ""
    @Published var selectedQuadrant: Quadrant = .importantUrgent
    @Published var composerOpen = false
    @Published var editing: TaskItem?
    @Published var imagePreview: Data?
    @Published var editorCloseRequest = 0
    /// 可逐项撤销的删除队列，末尾是最新删除的事项。
    @Published private(set) var undoQueue: [UndoEntry] = []
    @Published private(set) var notice: Notice?
    @Published var focusedTaskID: UUID?
    /// 主界面中展开查看描述的事项（单击切换，双击进入编辑）。
    @Published var expandedTaskIDs: Set<UUID> = []
    @Published var isDraggingTask = false
    /// 用于请求输入框聚焦（每次自增都会让视图重新获取焦点）。
    @Published var focusRequest = 0

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
            if focusInput { openComposer() }
            return
        }
        isExpanded = true
        controller?.panel.orderFrontRegardless()
        if focusInput {
            openComposer()
        } else {
            controller?.focusPanelIfNeeded()
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isPinned = false
        isExpanded = false
        composerOpen = false
        focusedTaskID = nil
    }

    func toggle(focusInput: Bool = false) {
        if isExpanded {
            collapse()
        } else {
            expand(focusInput: focusInput)
        }
    }

    func openComposer(quadrant: Quadrant? = nil) {
        if let quadrant { selectedQuadrant = quadrant }
        composerOpen = true
        controller?.focusPanelIfNeeded()
        // 等窗口真正成为 key window 后再要焦点，否则 SwiftUI 的焦点会被丢弃。
        DispatchQueue.main.async { [weak self] in
            self?.focusRequest += 1
        }
        expand()
    }

    // MARK: - 任务操作

    func submitDraft() {
        let parsed = DraftParser.parse(draft, fallback: selectedQuadrant)
        guard let title = parsed.title, !title.isEmpty else { return }
        repository.addTask(title: title, quadrant: parsed.quadrant, to: repository.allTasks())
        draft = ""
        selectedQuadrant = parsed.quadrant
        focusRequest += 1
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
        expandedTaskIDs.remove(id)
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

    func show(_ text: String, isError: Bool = false) {
        let notice = Notice(text: text, isError: isError)
        self.notice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 4 : 1.6)) { [weak self] in
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }

    func toggleCompletion(_ task: TaskItem) {
        repository.toggleCompletion(task)
    }

    func move(_ task: TaskItem, to quadrant: Quadrant) {
        repository.move(task, to: quadrant)
    }

    func commitEdit(title: String, note: String?, quadrant: Quadrant) {
        guard let task = editing else { return }
        repository.update(task, title: title, note: note, quadrant: quadrant)
        editing = nil
    }

    func toggleExpanded(_ task: TaskItem) {
        if expandedTaskIDs.remove(task.id) == nil { expandedTaskIDs.insert(task.id) }
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

/// 解析 `!1`–`!4` 前缀（PRD F5）。
enum DraftParser {
    static func parse(_ raw: String, fallback: Quadrant) -> (title: String?, quadrant: Quadrant) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, fallback) }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if let first = parts.first, first.count == 2, first.hasPrefix("!"),
           let number = Int(first.dropFirst()), let quadrant = Quadrant.from(shortcutNumber: number) {
            let rest = parts.count > 1 ? String(parts[1]) : ""
            let title = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? nil : String(title.prefix(200)), quadrant)
        }
        return (String(trimmed.prefix(200)), fallback)
    }
}
