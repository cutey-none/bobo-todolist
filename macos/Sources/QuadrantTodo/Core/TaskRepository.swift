import Foundation
import SwiftData

/// 任务读写入口，集中实现 PRD 4.2 的排序规则与写入时机（立即保存）。
/// 所有写操作都以本地保存成功为准：失败时回滚内存改动并返回失败，界面据此保留原状态。
struct TaskRepository {
    let context: ModelContext
    var attachments: AttachmentStore = .shared

    /// 验证用：模拟本地写入失败（测试或 `QT_FAIL_SAVES=1`）。
    static var simulatesSaveFailure = ProcessInfo.processInfo.environment["QT_FAIL_SAVES"] == "1"

    func allTasks() -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>()
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 未完成：sortOrder 升序，其次创建时间倒序。
    func activeTasks(in quadrant: Quadrant, from tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.quadrant == quadrant && !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// 已完成：completedAt 倒序，其次创建时间倒序。
    func completedTasks(in quadrant: Quadrant, from tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.quadrant == quadrant && $0.isCompleted }
            .sorted { lhs, rhs in
                let l = lhs.completedAt ?? lhs.createdAt
                let r = rhs.completedAt ?? rhs.createdAt
                if l != r { return l > r }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// 未完成列表末尾的排序值：新建与恢复未完成都追加到末尾。
    private func endSortOrder(in quadrant: Quadrant, from tasks: [TaskItem]) -> Int {
        (activeTasks(in: quadrant, from: tasks).map(\.sortOrder).max() ?? -1) + 1
    }

    /// 标题不合法或保存失败时返回 nil，且不留下任何事项。
    @discardableResult
    func addTask(title: String, quadrant: Quadrant, note: String? = nil, to tasks: [TaskItem]) -> TaskItem? {
        guard case .success(let valid) = TaskTitle.validate(title) else { return nil }
        let task = TaskItem(title: valid, note: note, quadrant: quadrant, sortOrder: endSortOrder(in: quadrant, from: tasks))
        context.insert(task)
        return save() ? task : nil
    }

    /// 一次保存标题、描述与象限；换象限时追加到目标象限末尾。
    @discardableResult
    func update(_ task: TaskItem, title: String, note: String?, quadrant: Quadrant) -> Bool {
        guard case .success(let valid) = TaskTitle.validate(title) else { return false }
        return persist([task]) {
            if task.quadrant != quadrant, !task.isCompleted {
                task.sortOrder = endSortOrder(in: quadrant, from: allTasks())
            }
            task.title = valid
            task.note = note
            task.quadrant = quadrant
            task.updatedAt = Date()
        }
    }

    /// 事项描述的 Markdown 文本；旧版结构化描述会即时转换。
    func description(for task: TaskItem) -> String {
        TaskDescription.markdown(fromStored: task.note, saveImage: attachments.save)
    }

    @discardableResult
    func saveDescription(_ markdown: String, for task: TaskItem) -> Bool {
        persist([task]) {
            task.note = TaskDescription.normalized(markdown)
            task.updatedAt = Date()
        }
    }

    /// 启动时把旧版 JSON 块描述一次性改写为 Markdown，图片转存为附件文件。
    func migrateLegacyDescriptionsToMarkdown(from tasks: [TaskItem]) {
        var migrated = false
        for task in tasks {
            guard let blocks = TaskDescription.legacyBlocks(from: task.note) else { continue }
            task.note = TaskDescription.normalized(TaskDescription.markdown(from: blocks, saveImage: attachments.save))
            task.updatedAt = Date()
            migrated = true
        }
        if migrated { save() }
    }

    func describedTaskIDs(from tasks: [TaskItem]) -> Set<UUID> {
        Set(tasks.compactMap { task in
            // `TaskDescription.normalized` stores nil for empty content, so presence can be
            // checked without repeatedly decoding embedded image data during list renders.
            guard let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else { return nil }
            return task.id
        })
    }

    func migrateLegacyProgressToDescriptions(from tasks: [TaskItem]) {
        var migrated = false
        for task in tasks {
            let entries = progress(for: task.id).sorted { $0.createdAt < $1.createdAt }
            guard !entries.isEmpty else { continue }
            var parts = [description(for: task).trimmingCharacters(in: .whitespacesAndNewlines)]
            for entry in entries {
                parts.append(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                if let image = entry.imageData, !image.isEmpty, let source = attachments.save(image) {
                    parts.append("![图片](\(source))")
                }
                context.delete(entry)
            }
            task.note = TaskDescription.normalized(parts.filter { !$0.isEmpty }.joined(separator: "\n\n"))
            task.updatedAt = Date()
            migrated = true
        }
        if migrated { save() }
    }

    @discardableResult
    func toggleCompletion(_ task: TaskItem) -> Bool {
        persist([task]) {
            if task.isCompleted {
                // 恢复未完成后追加到该象限未完成列表末尾（UI PRD 5.2 建议默认）。
                task.sortOrder = endSortOrder(in: task.quadrant, from: allTasks())
                task.completedAt = nil
            } else {
                task.completedAt = Date()
            }
            task.isCompleted.toggle()
            task.updatedAt = Date()
        }
    }

    /// 撤销一次完成 / 恢复：回到切换前的完成状态与原排序位置。
    @discardableResult
    func restoreCompletion(_ task: TaskItem, to state: CompletionState) -> Bool {
        persist([task]) {
            task.isCompleted = state.isCompleted
            task.completedAt = state.completedAt
            task.sortOrder = state.sortOrder
            task.updatedAt = Date()
        }
    }

    /// 键盘「上移 / 下移」：在所属象限未完成列表内移动，越界时停在两端。
    @discardableResult
    func reorder(_ task: TaskItem, by delta: Int) -> Bool {
        var list = activeTasks(in: task.quadrant, from: allTasks())
        guard let index = list.firstIndex(where: { $0.id == task.id }) else { return false }
        let target = min(max(index + delta, 0), list.count - 1)
        guard target != index else { return true }
        return persist(list) {
            list.remove(at: index)
            list.insert(task, at: target)
            for (order, item) in list.enumerated() { item.sortOrder = order }
            task.updatedAt = Date()
        }
    }

    @discardableResult
    func move(_ task: TaskItem, to quadrant: Quadrant, dropIndex: Int? = nil) -> Bool {
        let target = activeTasks(in: quadrant, from: allTasks()).filter { $0.id != task.id }
        let ordered: [TaskItem]
        if let index = dropIndex, index >= 0, index < target.count {
            ordered = Array(target[0..<index]) + [task] + Array(target[index...])
        } else {
            ordered = [task] + target
        }
        return persist(ordered) {
            task.quadrant = quadrant
            task.updatedAt = Date()
            for (index, item) in ordered.enumerated() {
                item.sortOrder = index
            }
        }
    }

    /// 删除成功返回可撤销的快照；保存失败时事项保留，返回 nil。
    func delete(_ task: TaskItem) -> TaskSnapshot? {
        let snapshot = TaskSnapshot(task)
        context.delete(task)
        return save() ? snapshot : nil
    }

    @discardableResult
    func restore(_ snapshot: TaskSnapshot) -> Bool {
        context.insert(snapshot.makeTask())
        return save()
    }

    /// 清理指定附件，保留其他事项或仍可撤销的删除所引用的文件。
    func removeUnusedAttachments(_ sources: [String], preserving notes: [String] = []) {
        // fetch 失败时不进行清理，避免误删无法读取的事项附件。
        guard let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) else { return }
        let references = tasks.compactMap(\.note) + notes
        for source in Set(sources) where !references.contains(where: { $0.contains(source) }) {
            attachments.remove(source)
        }
    }

    func progress(for taskID: UUID) -> [ProgressEntry] {
        let descriptor = FetchDescriptor<ProgressEntry>(predicate: #Predicate { $0.taskID == taskID },
                                                        sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addProgress(taskID: UUID, text: String, imageData: Data?) -> ProgressEntry {
        let entry = ProgressEntry(taskID: taskID, text: text.trimmingCharacters(in: .whitespacesAndNewlines), imageData: imageData)
        // An empty entry is returned detached; nothing is inserted or persisted.
        guard !entry.text.isEmpty || imageData != nil else { return entry }
        context.insert(entry)
        save()
        return entry
    }

    func deleteProgress(_ entry: ProgressEntry) {
        context.delete(entry)
        save()
    }

    func purgeOrphanProgress() {
        // A failed fetch must never be interpreted as an empty task database.
        guard let tasks = try? context.fetch(FetchDescriptor<TaskItem>()),
              let entries = try? context.fetch(FetchDescriptor<ProgressEntry>()) else { return }
        let ids = Set(tasks.map(\.id))
        for entry in entries where !ids.contains(entry.taskID) { context.delete(entry) }
        save()
    }

    func progressCounts() -> [UUID: Int] {
        let entries = (try? context.fetch(FetchDescriptor<ProgressEntry>())) ?? []
        return entries.reduce(into: [:]) { $0[$1.taskID, default: 0] += 1 }
    }

    /// 修改已有事项并保存；保存失败时把这些事项的字段逐一恢复原值。
    /// SwiftData 的 rollback 不会还原已加载对象的属性，因此需要显式快照。
    private func persist(_ tasks: [TaskItem], _ change: () -> Void) -> Bool {
        let before = tasks.map { (task: $0, fields: TaskFields($0)) }
        change()
        guard save() else {
            for item in before { item.fields.apply(to: item.task) }
            return false
        }
        return true
    }

    @discardableResult
    func save() -> Bool {
        do {
            if Self.simulatesSaveFailure { throw CocoaError(.fileWriteUnknown) }
            try context.save()
            return true
        } catch {
            NSLog("QuadrantTodo: 保存失败 \(error.localizedDescription)")
            // 丢弃未写入的内存改动，界面与磁盘保持一致。
            context.rollback()
            return false
        }
    }
}

/// 事项可变字段的快照，用于保存失败时还原。
private struct TaskFields {
    let title: String
    let note: String?
    let quadrantRaw: String
    let isCompleted: Bool
    let completedAt: Date?
    let sortOrder: Int
    let updatedAt: Date

    init(_ task: TaskItem) {
        title = task.title
        note = task.note
        quadrantRaw = task.quadrantRaw
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        sortOrder = task.sortOrder
        updatedAt = task.updatedAt
    }

    func apply(to task: TaskItem) {
        task.title = title
        task.note = note
        task.quadrantRaw = quadrantRaw
        task.isCompleted = isCompleted
        task.completedAt = completedAt
        task.sortOrder = sortOrder
        task.updatedAt = updatedAt
    }
}

/// 切换完成状态前的快照，供「撤销」恢复。
struct CompletionState {
    let isCompleted: Bool
    let completedAt: Date?
    let sortOrder: Int

    init(_ task: TaskItem) {
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        sortOrder = task.sortOrder
    }
}
