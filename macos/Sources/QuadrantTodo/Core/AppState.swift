import AppKit
import Combine
import SwiftUI

struct UndoEntry: Identifiable {
    let id = UUID()
    let snapshot: TaskSnapshot
    let title: String
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
    @Published var progressPreview: Data?
    @Published var undo: UndoEntry?
    @Published var focusedTaskID: UUID?
    @Published var isDraggingTask = false
    /// 用于请求输入框聚焦（每次自增都会让视图重新获取焦点）。
    @Published var focusRequest = 0

    weak var controller: PanelController?

    private var undoTimer: Timer?
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

    func delete(_ task: TaskItem) {
        // Replacing the single undo slot ends the previous deletion's grace period.
        if undo != nil { repository.purgeOrphanProgress() }
        let snapshot = repository.delete(task)
        undo = UndoEntry(snapshot: snapshot, title: task.title)
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: Metrics.undoWindow, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.undo = nil
                self?.repository.purgeOrphanProgress()
            }
        }
        if focusedTaskID == task.id { focusedTaskID = nil }
    }

    func performUndo() {
        guard let entry = undo else { return }
        repository.restore(entry.snapshot)
        undo = nil
        undoTimer?.invalidate()
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
