import Foundation
import SwiftData

/// 任务读写入口，集中实现 PRD 4.2 的排序规则与写入时机（立即保存）。
struct TaskRepository {
    let context: ModelContext
    var attachments: AttachmentStore = .shared

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

    @discardableResult
    func addTask(title: String, quadrant: Quadrant, note: String? = nil, to tasks: [TaskItem]) -> TaskItem {
        let top = activeTasks(in: quadrant, from: tasks).map(\.sortOrder).min() ?? 1
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note,
            quadrant: quadrant,
            sortOrder: top - 1
        )
        context.insert(task)
        save()
        return task
    }

    func update(_ task: TaskItem, title: String, note: String?, quadrant: Quadrant) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if task.quadrant != quadrant {
            let top = activeTasks(in: quadrant, from: allTasks()).map(\.sortOrder).min() ?? 1
            task.sortOrder = top - 1
        }
        task.title = trimmed
        task.note = note
        task.quadrant = quadrant
        task.updatedAt = Date()
        save()
    }

    /// 事项描述的 Markdown 文本；旧版结构化描述会即时转换。
    func description(for task: TaskItem) -> String {
        TaskDescription.markdown(fromStored: task.note, saveImage: attachments.save)
    }

    func saveDescription(_ markdown: String, for task: TaskItem) {
        task.note = TaskDescription.normalized(markdown)
        task.updatedAt = Date()
        save()
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

    func toggleCompletion(_ task: TaskItem) {
        task.isCompleted.toggle()
        if task.isCompleted {
            task.completedAt = Date()
        } else {
            // 取消完成后回到该象限未完成区顶部。
            task.completedAt = nil
            let top = activeTasks(in: task.quadrant, from: allTasks()).map(\.sortOrder).min() ?? 1
            task.sortOrder = top - 1
        }
        task.updatedAt = Date()
        save()
    }

    func move(_ task: TaskItem, to quadrant: Quadrant, dropIndex: Int? = nil) {
        let target = activeTasks(in: quadrant, from: allTasks()).filter { $0.id != task.id }
        let ordered: [TaskItem]
        if let index = dropIndex, index >= 0, index < target.count {
            ordered = Array(target[0..<index]) + [task] + Array(target[index...])
        } else {
            ordered = [task] + target
        }
        task.quadrant = quadrant
        task.updatedAt = Date()
        for (index, item) in ordered.enumerated() {
            item.sortOrder = index
        }
        save()
    }

    func delete(_ task: TaskItem) -> TaskSnapshot {
        let snapshot = TaskSnapshot(task)
        context.delete(task)
        save()
        return snapshot
    }

    func restore(_ snapshot: TaskSnapshot) {
        context.insert(snapshot.makeTask())
        save()
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

    func save() {
        do {
            try context.save()
        } catch {
            NSLog("QuadrantTodo: 保存失败 \(error.localizedDescription)")
        }
    }
}
