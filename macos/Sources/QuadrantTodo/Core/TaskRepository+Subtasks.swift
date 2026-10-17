import Foundation
import SwiftData

/// 子待办读写（PRD 15）：与事项一样立即保存，失败时回滚字段并返回失败。
extension TaskRepository {
    func allSubtasks() -> [SubtaskItem] {
        (try? context.fetch(FetchDescriptor<SubtaskItem>())) ?? []
    }

    func subtasks(of parentID: UUID) -> [SubtaskItem] {
        let descriptor = FetchDescriptor<SubtaskItem>(predicate: #Predicate { $0.parentID == parentID })
        return Self.ordered((try? context.fetch(descriptor)) ?? [])
    }

    /// sortOrder 升序，其次创建时间升序。
    static func ordered(_ items: [SubtaskItem]) -> [SubtaskItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        }
    }

    static func progress(of subtasks: [SubtaskItem]) -> [UUID: SubtaskProgress] {
        Dictionary(grouping: subtasks, by: \.parentID).mapValues { items in
            SubtaskProgress(done: items.filter(\.isCompleted).count, total: items.count)
        }
    }

    func task(withID id: UUID) -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 标题不合法或保存失败时返回 nil，且不留下任何子待办。
    @discardableResult
    func addSubtask(title: String, to parentID: UUID) -> SubtaskItem? {
        guard case .success(let valid) = TaskTitle.validate(title) else { return nil }
        let next = (subtasks(of: parentID).map(\.sortOrder).max() ?? -1) + 1
        let item = SubtaskItem(parentID: parentID, title: valid, sortOrder: next)
        context.insert(item)
        return save() ? item : nil
    }

    @discardableResult
    func renameSubtask(_ item: SubtaskItem, to title: String) -> Bool {
        guard case .success(let valid) = TaskTitle.validate(title) else { return false }
        return persistSubtasks([item]) {
            item.title = valid
            item.updatedAt = Date()
        }
    }

    /// 只切换子待办自身；父待办的完成状态不受影响（父子不联动）。
    @discardableResult
    func toggleSubtask(_ item: SubtaskItem) -> Bool {
        persistSubtasks([item]) {
            item.isCompleted.toggle()
            item.completedAt = item.isCompleted ? Date() : nil
            item.updatedAt = Date()
        }
    }

    /// 「上移 / 下移」：越界时停在两端。
    @discardableResult
    func moveSubtask(_ item: SubtaskItem, by delta: Int) -> Bool {
        let list = subtasks(of: item.parentID)
        guard let index = list.firstIndex(where: { $0.id == item.id }) else { return false }
        let target = min(max(index + delta, 0), list.count - 1)
        guard target != index else { return true }
        var reordered = list
        reordered.remove(at: index)
        reordered.insert(item, at: target)
        return resequence(reordered, touching: list)
    }

    /// 拖拽：放到 targetID 之前；targetID 为 nil 或不在同一父待办时放到末尾。
    @discardableResult
    func moveSubtask(_ item: SubtaskItem, before targetID: UUID?) -> Bool {
        let list = subtasks(of: item.parentID)
        var reordered = list.filter { $0.id != item.id }
        guard reordered.count == list.count - 1 else { return false }
        let index = targetID.flatMap { id in reordered.firstIndex { $0.id == id } } ?? reordered.count
        reordered.insert(item, at: index)
        return resequence(reordered, touching: list)
    }

    private func resequence(_ ordered: [SubtaskItem], touching items: [SubtaskItem]) -> Bool {
        persistSubtasks(items) {
            for (order, item) in ordered.enumerated() where item.sortOrder != order {
                item.sortOrder = order
                item.updatedAt = Date()
            }
        }
    }

    /// 删除成功返回带原位置的快照；保存失败时子待办保留，返回 nil。
    func deleteSubtask(_ item: SubtaskItem) -> SubtaskSnapshot? {
        let snapshot = SubtaskSnapshot(item, index: index(of: item))
        context.delete(item)
        return save() ? snapshot : nil
    }

    /// 放回原父待办的原位置；父待办已不存在时不恢复，返回 false。
    @discardableResult
    func restoreSubtask(_ snapshot: SubtaskSnapshot) -> Bool {
        guard task(withID: snapshot.parentID) != nil else { return false }
        let siblings = subtasks(of: snapshot.parentID)
        return persistSubtasks(siblings) { insert(snapshot, among: siblings) }
    }

    /// 提升为独立待办：在父待办所在象限新建事项（保留标题与完成状态），并移除该子待办。
    func promoteSubtask(_ item: SubtaskItem) -> (task: TaskItem, snapshot: SubtaskSnapshot)? {
        guard let parent = task(withID: item.parentID) else { return nil }
        let snapshot = SubtaskSnapshot(item, index: index(of: item))
        let promoted = TaskItem(
            title: item.title,
            quadrant: parent.quadrant,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt,
            sortOrder: endSortOrder(in: parent.quadrant, from: allTasks())
        )
        context.insert(promoted)
        context.delete(item)
        return save() ? (promoted, snapshot) : nil
    }

    /// 撤销提升：删除新建的待办（若仍存在），把子待办放回原位置；父待办已不存在时返回 false。
    @discardableResult
    func undoPromotion(_ snapshot: SubtaskSnapshot, promotedTaskID: UUID) -> Bool {
        guard task(withID: snapshot.parentID) != nil else { return false }
        let siblings = subtasks(of: snapshot.parentID)
        return persistSubtasks(siblings) {
            if let promoted = task(withID: promotedTaskID) { context.delete(promoted) }
            insert(snapshot, among: siblings)
        }
    }

    private func index(of item: SubtaskItem) -> Int {
        let list = subtasks(of: item.parentID)
        return list.firstIndex { $0.id == item.id } ?? list.count
    }

    /// 插入快照并重排兄弟顺序（不保存，由调用方的 persistSubtasks 负责）。
    private func insert(_ snapshot: SubtaskSnapshot, among siblings: [SubtaskItem]) {
        let item = snapshot.makeSubtask(sortOrder: 0)
        context.insert(item)
        var ordered = siblings
        ordered.insert(item, at: min(max(snapshot.index, 0), ordered.count))
        for (order, sibling) in ordered.enumerated() { sibling.sortOrder = order }
    }

    /// 修改已有子待办并保存；保存失败时逐一恢复字段（SwiftData 的 rollback 不还原已加载对象的属性）。
    func persistSubtasks(_ items: [SubtaskItem], _ change: () -> Void) -> Bool {
        let before = items.map { (item: $0, fields: SubtaskFields($0)) }
        change()
        guard save() else {
            for entry in before { entry.fields.apply(to: entry.item) }
            return false
        }
        return true
    }
}

/// 子待办可变字段的快照，用于保存失败时还原。
struct SubtaskFields {
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let sortOrder: Int
    let updatedAt: Date

    init(_ item: SubtaskItem) {
        title = item.title
        isCompleted = item.isCompleted
        completedAt = item.completedAt
        sortOrder = item.sortOrder
        updatedAt = item.updatedAt
    }

    func apply(to item: SubtaskItem) {
        item.title = title
        item.isCompleted = isCompleted
        item.completedAt = completedAt
        item.sortOrder = sortOrder
        item.updatedAt = updatedAt
    }
}
