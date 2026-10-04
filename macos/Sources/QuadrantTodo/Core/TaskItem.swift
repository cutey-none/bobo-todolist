import Foundation
import SwiftData

/// 任务数据模型（PRD 5.1）。
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String?
    var quadrantRaw: String
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var dueAt: Date?
    var sortOrder: Int
    var updatedAt: Date

    var quadrant: Quadrant {
        get { Quadrant(rawValue: quadrantRaw) ?? .importantUrgent }
        set { quadrantRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        quadrant: Quadrant = .importantUrgent,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        dueAt: Date? = nil,
        sortOrder: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.quadrantRaw = quadrant.rawValue
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.dueAt = dueAt
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    var sortKey: String { "\(sortOrder)-\(createdAt.timeIntervalSince1970)" }
}

/// 删除后可恢复的快照，用于 5 秒撤销。
struct TaskSnapshot {
    let id: UUID
    let title: String
    let note: String?
    let quadrant: Quadrant
    let isCompleted: Bool
    let createdAt: Date
    let completedAt: Date?
    let dueAt: Date?
    let sortOrder: Int

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        note = task.note
        quadrant = task.quadrant
        isCompleted = task.isCompleted
        createdAt = task.createdAt
        completedAt = task.completedAt
        dueAt = task.dueAt
        sortOrder = task.sortOrder
    }

    func makeTask() -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            note: note,
            quadrant: quadrant,
            isCompleted: isCompleted,
            createdAt: createdAt,
            completedAt: completedAt,
            dueAt: dueAt,
            sortOrder: sortOrder
        )
    }
}
